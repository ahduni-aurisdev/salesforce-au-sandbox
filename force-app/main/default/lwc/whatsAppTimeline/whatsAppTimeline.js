import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMessages from '@salesforce/apex/WhatsAppTimelineController.getMessages';

const TICKS = { Sent: '✓', Delivered: '✓✓', Read: '✓✓', Failed: '✕' };

export default class WhatsAppInbox extends LightningElement {
    @api recordId;
    wired;
    all = [];
    error;

    @wire(getMessages, { recordId: '$recordId' })
    wiredMessages(result) {
        this.wired = result;
        if (result.data) {
            this.all = result.data.map((m) => {
                const inbound = m.Direction__c === 'Inbound';
                const who = (m.Lead__r && m.Lead__r.Name) || (m.Contact__r && m.Contact__r.Name);
                const at = m.Sent_At__c || m.Received_At__c || m.Last_Event_At__c;
                return {
                    id: m.Id,
                    status: m.Status__c,
                    at,
                    day: at ? at.substring(0, 10) : '',
                    who,
                    sender: m.Sender_Number__c,
                    title: inbound ? (m.Message_Type__c && !['text', 'interactive', 'button'].includes(m.Message_Type__c) ? 'Reply · ' + m.Message_Type__c : 'Reply') : (m.Template_Name__c || m.Campaign_Name__c || m.Name),
                    attachment: m.Attachment_Name__c ? '📎 ' + m.Attachment_Name__c : (inbound && m.Message_Type__c && !['text', 'interactive', 'button'].includes(m.Message_Type__c) ? '📎 ' + m.Message_Type__c + (m.Media_Mime_Type__c ? ' (' + m.Media_Mime_Type__c + ')' : '') : null),
                    journey: m.Journey_Name__c,
                    text: m.Message_Text__c,
                    reason: m.Failure_Reason__c,
                    tick: inbound ? '' : TICKS[m.Status__c] || '',
                    rowClass: 'row ' + (inbound ? 'in' : 'out'),
                    bubbleClass: 'bubble ' + (inbound ? 'inbound' : m.Status__c === 'Failed' ? 'failed' : 'outbound'),
                    tickClass: 'tick ' + (m.Status__c || '').toLowerCase(),
                    steps: [
                        { key: 'recv', label: 'Received', at: m.Received_At__c },
                        { key: 'sent', label: 'Sent', at: m.Sent_At__c },
                        { key: 'delivered', label: 'Delivered', at: m.Delivered_At__c },
                        { key: 'read', label: 'Read', at: m.Read_At__c },
                        { key: 'failed', label: 'Failed', at: m.Failed_At__c }
                    ].filter((s) => s.at)
                };
            });
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error.body ? result.error.body.message : 'Unable to load messages';
        }
    }

    count(s) {
        return s === 'All' ? this.all.length : this.all.filter((m) => m.status === s).length;
    }

    get showWho() {
        // show the student name when the thread mixes several records (Account / Opportunity, or shared phone numbers)
        return new Set(this.all.map((m) => m.who).filter((w) => w)).size > 1 || this.recordIdIsGroup;
    }

    get recordIdIsGroup() {
        // Account / Opportunity (001 / 006) threads can mix several students
        return this.recordId && (this.recordId.startsWith('001') || this.recordId.startsWith('006'));
    }

    get days() {
        const visible = this.all;
        const groups = [];
        visible.forEach((m) => {
            let g = groups[groups.length - 1];
            if (!g || g.day !== m.day) {
                g = { day: m.day, at: m.at, items: [] };
                groups.push(g);
            }
            g.items.push({ ...m, whoLabel: this.showWho ? m.who : null });
        });
        return groups;
    }

    get hasMessages() {
        return this.all.length > 0;
    }

    get summary() {
        const read = this.count('Read');
        const replies = this.count('Received');
        const delivered = this.count('Delivered') + read;
        return `${this.all.length - replies} sent · ${delivered} delivered · ${read} read · ${this.count('Failed')} failed · ${replies} replies`;
    }

    handleRefresh() {
        refreshApex(this.wired);
    }
}