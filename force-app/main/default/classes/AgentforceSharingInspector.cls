/**
 * @description Invocable action for Agentforce / Einstein Copilot to review the latest share health.
 */
public inherited sharing class AgentforceSharingInspector {
    
    @InvocableMethod(label='Check Sharing Health' description='Retrieves the latest Sharing Validation Log summary.')
    public static List<String> checkSharingHealth(List<Id> projectResourceIds) {
        List<String> results = new List<String>();
        
        // Find the latest validation log
        List<Sharing_Audit_Log__c> latestLogs = [
            SELECT Id, Total_Expected__c, Total_Actual__c, Discrepancies_Found__c, Summary_Report__c, CreatedDate
            FROM Sharing_Audit_Log__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        if (latestLogs.isEmpty()) {
            for (Id prId : projectResourceIds) {
                results.add('0% Accurate. No Sharing Validation Logs found. Please run the SharingAuditBatch.');
            }
            return results;
        }
        
        Sharing_Audit_Log__c log = latestLogs[0];
        Decimal accuracy = 100.0;
        if (log.Total_Expected__c != null && log.Total_Expected__c > 0) {
            accuracy = ((log.Total_Expected__c - log.Discrepancies_Found__c) / log.Total_Expected__c) * 100.0;
        }
        
        String summary = accuracy.setScale(0) + '% Accurate, ' + log.Discrepancies_Found__c + ' missing shares found in last audit.\n\n';
        summary += 'Log details: ' + log.Summary_Report__c;
        
        for (Id prId : projectResourceIds) {
            // Returns the structured string for Agentforce to process
            results.add(summary);
        }
        
        return results;
    }
}
