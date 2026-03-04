// 1. Identify a target user for the demo (External User)
User demoUser = [SELECT Id FROM User WHERE IsActive = true AND UserType = 'Standard' LIMIT 1];
System.debug('Target Demo User: ' + demoUser.Id);

// 2. Create Parent Accounts (Optional, for context)
List<Account> testAccounts = new List<Account>();
for(Integer i=0; i<5; i++) {
    testAccounts.add(new Account(Name = 'NextEra Client - Region ' + i));
}
insert testAccounts;

// 3. Create Project Records (100-200 for demo scale)
List<Project_Resource__c> projects = new List<Project_Resource__c>();
for(Integer i=0; i<200; i++) {
    projects.add(new Project_Resource__c(
        Account__c = testAccounts[Math.mod(i, 5)].Id,
        Status__c = 'In Progress',
        External_ID__c = 'PRJ-EXT-' + i
    ));
}
insert projects;

// 4. Create Resource Assignments
// This triggers your "Chained Queueable" sharing logic
List<Resource_Assignment__c> assignments = new List<Resource_Assignment__c>();
for(Integer i=0; i<50; i++) {
    assignments.add(new Resource_Assignment__c(
        Project_Resource__c = projects[i].Id,
        User__c = demoUser.Id,
        Access_Level__c = 'Read'
    ));
}
insert assignments;

System.debug('Data Generation Complete. 200 Projects and 50 Assignments created.');