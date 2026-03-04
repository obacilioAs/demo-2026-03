// 1. Identify the 'Project Resources' that had their shares deleted
// We query for assignments that exist but have no corresponding manual share
List<Resource_Assignment__c> missingShares = [
    SELECT Project_Resource__c, User__c, Access_Level__c 
    FROM Resource_Assignment__c 
    WHERE Project_Resource__c NOT IN (
        SELECT ParentId FROM Project_Resource__Share WHERE RowCause = 'Manual'
    )
];

System.debug('Discrepancies identified: ' + missingShares.size());

if (!missingShares.isEmpty()) {
    // 2. Call your Service Layer to handle the repair.
    // This triggers the Chained Queueable logic you will be demoing.
    SharingService.processSharing(missingShares);
    
    System.debug('Repair initiated via Chained Queueable framework.');
} else {
    System.debug('No discrepancies found. Security is already in sync.');
}