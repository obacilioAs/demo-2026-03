/**
 * @description High-Scale Queueable framework for calculating manual apex shares.
 * 
 * ARCHITECTURE NOTES:
 * This architecture avoids CPU Timeouts and 101 SOQL Limits during mass updates by:
 * 1. Chaining Context: It limits the records processed in a single transaction (BATCH_LIMIT = 2000). 
 * 2. If the current payload exceeds this safe batch size, it evaluates Limits.getQueueableJobs().
 *    If limits allow, it self-chains by enqueuing a new instance of SharingProcessor with the remaining records.
 * 3. Smart DML (Aggregate SOQL): Rather than querying every single Project_Resource__Share record 
 *    (which could blow up the heap and SOQL row limits), it uses an Aggregate query to fetch the 
 *    maximum existing access level per User/Resource combination. This allows us to skip unnecessary 
 *    DML inserts, further avoiding DML Exceptions and saving CPU processing time.
 */
public class SharingProcessor implements Queueable {
    private List<Resource_Assignment__c> recordsToProcess;
    
    // Configurable limit per queueable execution to stay under DML and CPU limits
    private static final Integer BATCH_LIMIT = 2000;

    public SharingProcessor(List<Resource_Assignment__c> recordsToProcess) {
        this.recordsToProcess = recordsToProcess;
    }
    
    public void execute(QueueableContext context) {
        if (recordsToProcess == null || recordsToProcess.isEmpty()) {
            return;
        }

        List<Resource_Assignment__c> currentBatch = new List<Resource_Assignment__c>();
        List<Resource_Assignment__c> remainingBatch = new List<Resource_Assignment__c>();
        
        // Split records into current transaction and next chain context
        for (Integer i = 0; i < recordsToProcess.size(); i++) {
            if (i < BATCH_LIMIT) {
                currentBatch.add(recordsToProcess.get(i));
            } else {
                remainingBatch.add(recordsToProcess.get(i));
            }
        }
        
        // Process current block leveraging the Service layer logic
        SharingService.calculateShares(currentBatch);
        
        // Chain the queueable if we have remaining records avoiding governor limits
        if (!remainingBatch.isEmpty()) {
            // Check Limits to ensure we can enqueue another job
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new SharingProcessor(remainingBatch));
            } else {
                System.debug(LoggingLevel.ERROR, 'Queueable Job Limit Exceeded when attempting to chain.');
            }
        }
    }
}
