/**
 * @description High-Scale Batch class to verify sharing accuracy. Runs nightly.
 * Compares Expected Shares (Resource_Assignment__c) against Actual (Project_Resource__Share).
 * 
 * ARCHITECTURE NOTES:
 * Runs asynchronously via Database.Batchable. Uses Statefulness to tally global success counters.
 * Prevents CPU timeouts during nightly audits by chunking validation.
 */
public class SharingReconciliationBatch implements Database.Batchable<sObject>, Database.Stateful {
    
    private Integer totalExpected = 0;
    private Integer totalActual = 0;
    private Integer discrepanciesFound = 0;
    private String mismatchCSV = 'ProjectResourceId,UserId,ExpectedAccess,ActualAccess\n';
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query Active Resource Assignments
        return Database.getQueryLocator([
            SELECT Id, Project_Resource__c, User__c, Access_Level__c 
            FROM Resource_Assignment__c
            WHERE Project_Resource__c != null AND User__c != null
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Resource_Assignment__c> scope) {
        // Delegate reconciliation logic to the centralized SharingService framework
        SharingService.ReconciliationResult result = SharingService.reconcileShares(scope);
        
        this.totalExpected += result.totalExpected;
        this.totalActual += result.totalActual;
        this.discrepanciesFound += result.discrepanciesFound;
        this.mismatchCSV += result.mismatchCSV;
    }
    
    public void finish(Database.BatchableContext bc) {
        // Save execution details and CSV mismatch in Sharing_Audit_Log__c
        Sharing_Audit_Log__c log = new Sharing_Audit_Log__c();
        log.Total_Expected__c = totalExpected;
        log.Total_Actual__c = totalActual;
        log.Discrepancies_Found__c = discrepanciesFound;
        log.Status__c = discrepanciesFound == 0 ? 'Passed' : 'Failed';
        
        log.Summary_Report__c = 'Audit completed on ' + System.now() + '.\n' +
            'Out of ' + totalExpected + ' assignments, found ' + totalActual + ' actual shares.\n' +
            discrepanciesFound + ' mismatches were detected.';
            
        try {
            insert log;
            
            // Save CSV as a ContentVersion if there are mismatches
            if (discrepanciesFound > 0) {
                ContentVersion cv = new ContentVersion();
                cv.Title = 'Audit_Mismatches_' + System.now().format();
                cv.PathOnClient = 'Audit_Mismatches.csv';
                cv.VersionData = Blob.valueOf(mismatchCSV);
                cv.FirstPublishLocationId = log.Id;
                insert cv;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to insert Audit Log or CSV: ' + e.getMessage());
        }
    }
}
