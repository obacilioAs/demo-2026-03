trigger ResourceAssignmentTrigger on Resource_Assignment__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ResourceAssignmentTriggerHandler.afterInsertUpdate(Trigger.new);
        }
    }
}
