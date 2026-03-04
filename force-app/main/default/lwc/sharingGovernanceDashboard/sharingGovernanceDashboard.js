import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getGlobalHealth from '@salesforce/apex/SharingService.getGlobalHealth';
import getRecordHealth from '@salesforce/apex/SharingService.getRecordHealth';
import triggerSystemAudit from '@salesforce/apex/SharingService.triggerSystemAudit';
import getLatestDiscrepancyReportId from '@salesforce/apex/SharingService.getLatestDiscrepancyReportId';

export default class SharingGovernanceDashboard extends NavigationMixin(LightningElement) {
    @api recordId; // Present only on Record Page
    
    @track healthScore = 0;
    @track statusMessage = 'Loading...';
    @track missingShares = 0;
    @track reportId = null;
    @track isAuditing = false;
    @track isRefreshing = false;
    
    // Store wired results for refreshApex
    wiredGlobalResult;
    wiredRecordResult;
    
    // Determine context
    get isHomePage() {
        return !this.recordId;
    }
    
    get cardTitle() {
        return this.isHomePage ? 'Global Sharing Governance Health' : 'Record Sharing Health';
    }
    
    get hasDiscrepancies() {
        return this.missingShares > 0;
    }
    
    // UI Styling for the Meter
    get ringVariant() {
        if (this.healthScore >= 99) return 'base-autocomplete'; // Green
        if (this.healthScore >= 90) return 'warning';
        return 'expired'; // Red
    }
    
    get progressRingClass() {
        let baseClass = 'slds-text-align_center ring-wrapper ';
        if (this.healthScore >= 99) return baseClass + 'ring-green';
        if (this.healthScore >= 90) return baseClass + 'ring-yellow';
        return baseClass + 'ring-red';
    }
    
    get textColorClass() {
        if (this.healthScore >= 99) return 'slds-text-color_success';
        if (this.healthScore >= 90) return 'text-yellow';
        return 'slds-text-color_error';
    }

    // Call Global or Record specific methods based on context
    @wire(getGlobalHealth)
    wiredGlobalHealth(result) {
        this.wiredGlobalResult = result;
        if (this.isHomePage) {
            this.handleHealthData(result.data, result.error);
        }
    }
    
    @wire(getRecordHealth, { recordId: '$recordId' })
    wiredRecordHealth(result) {
        this.wiredRecordResult = result;
        if (!this.isHomePage && this.recordId) {
            this.handleHealthData(result.data, result.error);
        }
    }
    
    handleHealthData(data, error) {
        if (data) {
            this.healthScore = data.scorePercentage || 0;
            this.statusMessage = data.statusMessage || 'No data found.';
            this.missingShares = data.missingShares || 0;
            this.reportId = data.reportId;
        } else if (error) {
            this.statusMessage = 'Error loading sharing health.';
            this.showToast('Error', error.body?.message || 'Unknown error occurred.', 'error');
        }
    }
    
    handleTriggerAudit() {
        this.isAuditing = true;
        triggerSystemAudit()
            .then(result => {
                this.showToast('Success', result, 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to trigger audit.', 'error');
                this.isAuditing = false;
            });
    }
    
    handleDownloadReport() {
        if (!this.reportId) return;
        
        getLatestDiscrepancyReportId({ logId: this.reportId })
            .then(docId => {
                if(docId) {
                    // Navigate to download the ContentDocument
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: {
                            url: `/sfc/servlet.shepherd/document/download/${docId}`
                        }
                    });
                } else {
                    this.showToast('Not Found', 'The Discrepancy CSV could not be located.', 'warning');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to retrieve download link.', 'error');
            });
    }
    
    handleRefreshData() {
        this.isRefreshing = true;
        
        let refreshPromises = [];
        if (this.isHomePage && this.wiredGlobalResult) {
            refreshPromises.push(refreshApex(this.wiredGlobalResult));
        } else if (!this.isHomePage && this.wiredRecordResult) {
            refreshPromises.push(refreshApex(this.wiredRecordResult));
        }
        
        Promise.all(refreshPromises)
            .then(() => {
                this.showToast('Success', 'Data refreshed successfully.', 'success');
            })
            .catch(error => {
                this.showToast('Error', 'Failed to refresh data.', 'error');
            })
            .finally(() => {
                this.isRefreshing = false;
            });
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
