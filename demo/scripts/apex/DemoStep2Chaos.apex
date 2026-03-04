// Simulate a "System Glitch" by deleting some sharing records manually
List<Project_Resource__Share> sharesToDelete = [
    SELECT Id FROM Project_Resource__Share 
    WHERE RowCause = 'Manual' 
    LIMIT 10
];
delete sharesToDelete;

System.debug('Chaos Injected: 10 Sharing records removed. Ready to run Auditor Batch.');