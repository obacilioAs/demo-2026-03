/**
 * @description Architecture Demo - Core Service layer for handling Project Resource sharing calculations, 
 * reconciliation, and providing data to the LWC Dashboard.
 * 
 * Centralizing logic here ensures that the Trigger, Queueable, Batch and LWC controllers share 
 * the exact same rules of engagement while remaining decoupled from operational execution.
 */
public inherited sharing class SharingService {
    
    // --- TRIGGER / PROCESSOR LOGIC ---
    
    /**
     * @description Initiates the async sharing calculation for large volumes
     * @param assignments The newly inserted or updated Resource assignments
     */
    public static void processSharing(List<Resource_Assignment__c> assignments) {
        if (assignments == null || assignments.isEmpty()) {
            return;
        }
        
        // Enforce scalable bulkified processing by delegating to our Chained Queueable Framework
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new SharingProcessor(assignments));
        } else {
            System.debug(LoggingLevel.ERROR, 'Queueable Job Limit Hit in Trigger. Cannot enqueue SharingProcessor.');
        }
    }
    
    /**
     * @description Core business logic to insert shares optimally. Designed to be called by SharingProcessor.
     */
    public static void calculateShares(List<Resource_Assignment__c> assignmentsToProcess) {
        Set<Id> parentIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        
        Map<String, String> requestedAccess = new Map<String, String>();
        
        for (Resource_Assignment__c assignment : assignmentsToProcess) {
            if (assignment.Project_Resource__c != null && assignment.User__c != null) {
                parentIds.add(assignment.Project_Resource__c);
                userIds.add(assignment.User__c);
                
                String key = assignment.Project_Resource__c + '-' + assignment.User__c;
                String incomingAccess = (assignment.Access_Level__c == 'Edit') ? 'Edit' : 'Read';
                
                String currentBest = requestedAccess.get(key);
                if (currentBest == null || incomingAccess == 'Edit') {
                    requestedAccess.put(key, incomingAccess);
                }
            }
        }
        
        // Use Aggregate SOQL queries to determine current sharing states to minimize DML operations
        for (AggregateResult ar : [
            SELECT ParentId, UserOrGroupId, MAX(AccessLevel) maxAccess
            FROM Project_Resource__Share
            WHERE ParentId IN :parentIds AND UserOrGroupId IN :userIds
            GROUP BY ParentId, UserOrGroupId
        ]) {
            Id parentId = (Id) ar.get('ParentId');
            Id userId = (Id) ar.get('UserOrGroupId');
            String key = parentId + '-' + userId;
            
            // If the map contains this key, check if we actually need to change it
            if (requestedAccess.containsKey(key)) {
                String reqLvl = requestedAccess.get(key);
                String exLvl = (String) ar.get('maxAccess');
                
                // If it already has Edit, or it requested Read and already has Read or Edit
                if (exLvl == 'Edit' || (exLvl == 'Read' && reqLvl == 'Read') || exLvl == 'All') {
                    requestedAccess.remove(key); // Already has sufficient access, no DML needed
                }
            }
        }
        
        List<Project_Resource__Share> sharesToInsert = new List<Project_Resource__Share>();
        for (String key : requestedAccess.keySet()) {
            String[] parts = key.split('-');
            Project_Resource__Share newShare = new Project_Resource__Share(
                ParentId = parts[0],
                UserOrGroupId = parts[1],
                AccessLevel = requestedAccess.get(key),
                RowCause = Schema.Project_Resource__Share.RowCause.Manual
            );
            sharesToInsert.add(newShare);
        }
        
        if (!sharesToInsert.isEmpty()) {
            try {
                insert sharesToInsert;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Failed to insert shares: ' + e.getMessage());
            }
        }
    }
    
    // --- RECONCILIATION LOGIC ---
    
    public class ReconciliationResult {
        public Integer totalExpected = 0;
        public Integer totalActual = 0;
        public Integer discrepanciesFound = 0;
        public String mismatchCSV = '';
    }
    
    /**
     * @description Core business logic to validate requested vs actual sharing access.
     */
    public static ReconciliationResult reconcileShares(List<Resource_Assignment__c> assignments) {
        ReconciliationResult result = new ReconciliationResult();
        Set<Id> parentIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        
        for (Resource_Assignment__c assignment : assignments) {
            parentIds.add(assignment.Project_Resource__c);
            userIds.add(assignment.User__c);
            result.totalExpected++;
        }
        
        // Use a Map-based comparison for Actual Shares
        Map<String, String> actualShares = new Map<String, String>();
        for (Project_Resource__Share share : [
            SELECT ParentId, UserOrGroupId, AccessLevel 
            FROM Project_Resource__Share 
            WHERE ParentId IN :parentIds AND UserOrGroupId IN :userIds
        ]) {
            actualShares.put(share.ParentId + '-' + share.UserOrGroupId, share.AccessLevel);
        }
        
        for (Resource_Assignment__c assignment : assignments) {
            String key = assignment.Project_Resource__c + '-' + assignment.User__c;
            String expectedAccess = assignment.Access_Level__c == 'Edit' ? 'Edit' : 'Read';
            String actualAccess = actualShares.get(key);
            
            if (actualAccess != null) {
                result.totalActual++;
            }
            
            // Check if there is a discrepancy in presence or access-level
            if (actualAccess == null || (expectedAccess == 'Edit' && actualAccess == 'Read')) {
                result.discrepanciesFound++;
                result.mismatchCSV += assignment.Project_Resource__c + ',' + assignment.User__c + ',' + expectedAccess + ',' + (actualAccess == null ? 'None' : actualAccess) + '\n';
            }
        }
        return result;
    }
    
    // --- LWC DASHBOARD LOGIC ---
    
    public class HealthScore {
        @AuraEnabled public Decimal scorePercentage;
        @AuraEnabled public String statusMessage;
        @AuraEnabled public Integer missingShares;
        @AuraEnabled public String reportId;
    }

    /**
     * @description Retrieves the latest global generic organizational sharing health.
     */
    @AuraEnabled(cacheable=true)
    public static HealthScore getGlobalHealth() {
        HealthScore health = new HealthScore();
        health.scorePercentage = 0;
        health.statusMessage = '0% Accurate. No Global Audits Found.';
        health.missingShares = 0;
        
        List<Sharing_Audit_Log__c> latestLogs = [
            SELECT Id, Total_Expected__c, Total_Actual__c, Discrepancies_Found__c, CreatedDate
            FROM Sharing_Audit_Log__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (!latestLogs.isEmpty()) {
            Sharing_Audit_Log__c log = latestLogs[0];
            health.reportId = log.Id;
            health.missingShares = Integer.valueOf(log.Discrepancies_Found__c);
            
            if (log.Total_Expected__c != null && log.Total_Expected__c > 0) {
                Decimal accuracy = ((log.Total_Expected__c - log.Discrepancies_Found__c) / log.Total_Expected__c) * 100.0;
                health.scorePercentage = accuracy.setScale(1);
            } else {
                health.scorePercentage = 100;
            }
            
            String logDate = log.CreatedDate.format('MMM d');
            health.statusMessage = 'Last Global Audit: ' + logDate + ' - ' + health.scorePercentage + '% Accurate';
        }
        
        return health;
    }

    /**
     * @description Retrieves health specifically for a single Project Resource record.
     */
    @AuraEnabled(cacheable=true)
    public static HealthScore getRecordHealth(Id recordId) {
        HealthScore health = new HealthScore();
        health.scorePercentage = 100;
        health.statusMessage = '100% Secure. Record sharing accurately aligned.';
        health.missingShares = 0;
        
        List<Resource_Assignment__c> assignments = [
            SELECT Id, Project_Resource__c, User__c, Access_Level__c 
            FROM Resource_Assignment__c 
            WHERE Project_Resource__c = :recordId AND User__c != null
        ];
        
        if(!assignments.isEmpty()) {
            ReconciliationResult result = reconcileShares(assignments);
            health.missingShares = result.discrepanciesFound;
            
            if (result.totalExpected > 0) {
                Decimal accuracy = ((result.totalExpected - result.discrepanciesFound) / (Decimal)result.totalExpected) * 100.0;
                health.scorePercentage = accuracy.setScale(1);
            }
            if(health.scorePercentage < 100) {
                health.statusMessage = health.scorePercentage + '% Accurate. Discrepancies found on this record.';
            }
        } else {
             health.statusMessage = 'No assignments found for this record.';
        }
        
        return health;
    }
    
    /**
     * @description Triggers the nightly batch manually from the UI.
     */
    @AuraEnabled
    public static String triggerSystemAudit() {
        try {
            Database.executeBatch(new SharingReconciliationBatch(), 2000);
            return 'Audit Batch queued successfully.';
        } catch (Exception e) {
            throw new AuraHandledException('Error queuing batch: ' + e.getMessage());
        }
    }
    
    /**
     * @description Retrieves the ContentDocumentId for the CSV attached to a log
     */
    @AuraEnabled(cacheable=false)
    public static Id getLatestDiscrepancyReportId(Id logId) {
        if(logId == null) return null;
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :logId
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if(!links.isEmpty()) {
            return links[0].ContentDocumentId;
        }
        return null;
    }
}
