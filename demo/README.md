# High-Scale Manual Apex Sharing & AI Governance Demo

This repository demonstrates a complete, deployable technical demo for a Salesforce "Manual Apex Sharing & AI Governance" framework capable of handling 10,000+ records without hitting governor limits.

## New UI Features

*   **Sharing Governance Dashboard (LWC)**: A dual-purpose LWC `sharingGovernanceDashboard` designed for both Record Pages and Home Pages.
    *   **Record Page**: Displays a precise Sharing Health Ring specifically for real-time status indicating if this record’s manual shares accurately reflect its Resource Assignment records.
    *   **Home Page**: Displays the Global Health over the entire Organization based on the nightly Reconciliation Batch. Includes the ability to *Trigger System Audit* manually from the UI, and download the latest identified discrepancies CSV.

## Architecture

*   **Data Model**: 
    *   `Project_Resource__c`: Target record that needs sharing.
    *   `Resource_Assignment__c`: Represents a User's assignment to a Project.
    *   `Sharing_Audit_Log__c`: Used to audit and store the expected vs actual sharing state.
*   **Trigger & Handler**: `ResourceAssignmentTrigger` fires on insert/update of assignments and delegates processing to `SharingService`.
*   **Service Layer (`SharingService.cls`)**: Encapsulates the entry point for sharing calculation, keeping triggers clean. Exposes endpoints to the LWC via `@AuraEnabled(cacheable=true)` to ensure high performance on Home vs Record pages.
*   **Chained Queueable Framework (`SharingProcessor.cls`)**: 
    *   Fully bulkified and designed for scale. Checks `Limits.getQueueableJobs()` to re-enqueue.
    *   Uses Aggregate SOQL to assess current sharing limits and determine minimal required DML.
    *   Re-enqueues itself if the current payload exceeds the safe batch size (preventing DML/CPU limit exceptions).
*   **The Auditor (`SharingReconciliationBatch.cls`)**: A high-scale Batch class that compares theoretical access vs actual access. Discrepancies are logged into a CSV and attached to a `Sharing_Audit_Log__c` record as a `ContentVersion` document.

## Agentforce & AI Integration

Includes an `@InvocableMethod` meant to be plugged into Agentforce or an Einstein Copilot action which reviews `Sharing_Audit_Log__c`.

## Deployment

1. Ensure your Salesforce org is authorized by running `sf org login web`.
2. Deploy the source: `sf project deploy start`
