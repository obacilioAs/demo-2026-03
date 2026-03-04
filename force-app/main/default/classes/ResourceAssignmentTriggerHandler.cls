/**
 * @description Fully bulkified trigger handler for Resource_Assignment__c
 */
public inherited sharing class ResourceAssignmentTriggerHandler {
    public static void afterInsertUpdate(List<Resource_Assignment__c> newList) {
        SharingService.processSharing(newList);
    }
}
