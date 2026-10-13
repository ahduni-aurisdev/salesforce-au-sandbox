public with sharing class LeadConvertController {

    // ── IMPORTANT: Replace these with your actual API names ─────────────────
    // Lead custom fields pointing to existing Account/Contact
    private static final String LEAD_ACCOUNT_FIELD = 'Account__c';
    private static final String LEAD_CONTACT_FIELD = 'Contact__c';

    // Your custom Opportunity Record Type DeveloperName
    private static final String OPP_RECORD_TYPE_DEV_NAME = 'CDC'; // ← CHANGE THIS

    // Your Org Account Record Type DeveloperName
    private static final String ORG_ACCOUNT_RT_DEV_NAME  = 'CDC';          // ← CHANGE THIS
    // ─────────────────────────────────────────────────────────────────────────


    /**
     * Fetch Lead details + pre-populated Account, Contact, Opportunity fields
     */
    @AuraEnabled(cacheable=true)
    public static LeadConvertWrapper getLeadDetails(Id leadId) {
        Lead lead = [
            SELECT Id, FirstName, LastName, Company, Email, Phone,
                   MobilePhone, Title, Website, AnnualRevenue, NumberOfEmployees,
                   Street, City, State, PostalCode, Country,
                   Account__c, Account__r.Name, Academic_Year__c,
                   Contact__c, Contact__r.Name, Drive_Type__c,
                   RecordTypeId, RecordType.Name,
                   OwnerId, Owner.Name,
                   LeadSource, Industry, Description
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        LeadConvertWrapper wrapper    = new LeadConvertWrapper();
        wrapper.lead                  = lead;
        wrapper.accountId             = lead.Account__c;
        wrapper.accountName           = lead.Account__c != null ? lead.Account__r.Name : '';
        wrapper.contactId             = lead.Contact__c;
        wrapper.contactName           = lead.Contact__c != null ? lead.Contact__r.Name : '';
        wrapper.opportunityName       = lead.Drive_Type__c + '_' + lead.Academic_Year__c + ' - ' + lead.FirstName + ' ' + lead.LastName;
        wrapper.convertedStatuses     = getConvertedStatuses();

        // Pass Opportunity Record Type name to LWC for display
        RecordType oppRt = getOppRecordType();
        wrapper.oppRecordTypeName = oppRt != null ? oppRt.Name : '';

        return wrapper;
    }

    /**
     * Fetch converted Lead statuses for the picklist
     */
    @AuraEnabled(cacheable=true)
    public static List<StatusOption> getConvertedStatuses() {
        List<StatusOption> options = new List<StatusOption>();
        for (LeadStatus ls : [
            SELECT MasterLabel FROM LeadStatus
            WHERE IsConverted = true
            ORDER BY MasterLabel
        ]) {
            options.add(new StatusOption(ls.MasterLabel, ls.MasterLabel));
        }
        return options;
    }

    /**
     * Main conversion method.
     * Step 1 — Convert Lead with DoNotCreateOpportunity = true
     *           (bypasses standard field mapping entirely)
     * Step 2 — Manually create Opportunity with custom Record Type
     *           and your own field mapping from the Lead
     */
    @AuraEnabled
    public static ConversionResult convertLead(
        Id      leadId,
        Id      accountId,
        Id      contactId,
        String  opportunityName,
        Boolean createOpportunity,
        String  convertedStatus
    ) {
        Savepoint sp = Database.setSavepoint();
        try {

            // ── Fetch Lead for custom field mapping ──────────────────────────
            Lead lead = [
                SELECT Id, FirstName, LastName, Company, Email, Phone, Expected_Students__c,
                       MobilePhone, Title, Website, AnnualRevenue, Proposed_Date__c, 
                       NumberOfEmployees, LeadSource, Industry, Academic_Year__c,
                       Description, OwnerId, CDC_Program__c, Drive_Type__c,
                       Street, City, State, PostalCode, Country,
                       Account__c, Contact__c
                FROM Lead
                WHERE Id = :leadId
                LIMIT 1
            ];

            // ── Step 1: Convert Lead — NO Opportunity created by Salesforce ──
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            lc.setConvertedStatus(convertedStatus);
            lc.setDoNotCreateOpportunity(true);   // ← Key: skip standard Opp creation
            lc.setOverwriteLeadSource(false);
            lc.setSendNotificationEmail(false);

            if (accountId != null) {
                lc.setAccountId(accountId);
            }
            if (contactId != null) {
                lc.setContactId(contactId);
            }

            Database.LeadConvertResult result = Database.convertLead(lc);

            if (!result.isSuccess()) {
                String errors = '';
                for (Database.Error err : result.getErrors()) {
                    errors += err.getMessage() + ' ';
                }
                throw new AuraHandledException(errors.trim());
            }

            Id convertedAccountId = result.getAccountId();
            Id convertedContactId = result.getContactId();

            // ── Post-conversion: fix Account Record Type if newly created ────
            if (convertedAccountId != null && accountId == null) {
                Id orgRtId = getOrgAccountRecordTypeId();
                if (orgRtId != null) {
                    update new Account(Id = convertedAccountId, RecordTypeId = orgRtId);
                }
            }

            // ── Step 2: Manually create Opportunity with custom mapping ──────
            Id createdOpportunityId;
            if (createOpportunity && String.isNotBlank(opportunityName)) {
                createdOpportunityId = createCustomOpportunity(
                    lead,
                    opportunityName,
                    convertedAccountId,
                    convertedContactId
                );
            }

            ConversionResult cr = new ConversionResult();
            cr.success       = true;
            cr.message       = 'Lead converted successfully!';
            cr.accountId     = convertedAccountId;
            cr.contactId     = convertedContactId;
            cr.opportunityId = createdOpportunityId;
            return cr;

        } catch (Exception e) {
            Database.rollback(sp);
            throw new IllegalArgumentException('ERROR: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString());
        }
    }


    // ── Private Helpers ──────────────────────────────────────────────────────

    /**
     * Creates Opportunity manually with your custom Record Type.
     *
     * ════════════════════════════════════════════════════════════════
     *  HOW TO ADD YOUR FIELD MAPPINGS
     *  Left side  = Opportunity field API name  (your custom RT fields)
     *  Right side = Lead field API name         (source value)
     *
     *  Standard Lead fields available:
     *    lead.FirstName, lead.LastName, lead.Company
     *    lead.Email, lead.Phone, lead.MobilePhone
     *    lead.Title, lead.Website
     *    lead.LeadSource, lead.Industry, lead.Description
     *    lead.AnnualRevenue, lead.NumberOfEmployees
     *    lead.Street, lead.City, lead.State, lead.PostalCode, lead.Country
     *    lead.OwnerId
     * ════════════════════════════════════════════════════════════════
     */
    private static Id createCustomOpportunity(
        Lead   lead,
        String opportunityName,
        Id     accountId,
        Id     contactId
    ) {
        RecordType oppRt = getOppRecordType();

        Opportunity opp = new Opportunity();

        // ── Required standard fields ─────────────────────────────────────────
        opp.Name      = opportunityName;
        opp.AccountId = accountId;
        opp.StageName = 'Planned';            // ← Replace with your default Stage
        opp.CloseDate = Date.today().addDays(30); // ← Replace with your default Close Date logic
        opp.OwnerId   = lead.OwnerId;

        // ── Record Type ──────────────────────────────────────────────────────
        if (oppRt != null) {
            opp.RecordTypeId = oppRt.Id;
        }

        // ════════════════════════════════════════════════════════════════════
        // ▼▼▼  YOUR CUSTOM FIELD MAPPINGS — edit these to match your org  ▼▼▼
        // ════════════════════════════════════════════════════════════════════

        // Standard Opportunity fields mapped from Lead
        opp.LeadSource  = lead.LeadSource;
        opp.Description = lead.Description;

        // Custom field mappings — replace left-side API names with yours:
        opp.Academic_Year__c       = lead.Academic_Year__c;
        opp.Program__c             = lead.CDC_Program__c;
        opp.Drive_Type__c          = lead.Drive_Type__c;
        opp.Drive_Date__c            = lead.Proposed_Date__c;
        opp.Expected_Students__c           = lead.Expected_Students__c;

        // ════════════════════════════════════════════════════════════════════
        // ▲▲▲  END OF FIELD MAPPINGS                                      ▲▲▲
        // ════════════════════════════════════════════════════════════════════

        insert opp;

        // ── Link Contact via OpportunityContactRole ──────────────────────────
        if (contactId != null) {
            insert new OpportunityContactRole(
                OpportunityId = opp.Id,
                ContactId     = contactId,
                Role          = 'Decision Maker',            // ← adjust role as needed
                IsPrimary     = true
            );
        }

        return opp.Id;
    }

    /**
     * Get the custom Opportunity Record Type
     */
    private static RecordType getOppRecordType() {
        List<RecordType> rtList = [
            SELECT Id, Name FROM RecordType
            WHERE SObjectType  = 'Opportunity'
            AND   DeveloperName = :OPP_RECORD_TYPE_DEV_NAME
            AND   IsActive      = true
            LIMIT 1
        ];
        return rtList.isEmpty() ? null : rtList[0];
    }

    /**
     * Get Organization (non-Person) Account Record Type
     */
    private static Id getOrgAccountRecordTypeId() {
        List<RecordType> rtList = [
            SELECT Id FROM RecordType
            WHERE SObjectType   = 'Account'
            AND   DeveloperName = :ORG_ACCOUNT_RT_DEV_NAME
            AND   IsPersonType  = false
            AND   IsActive      = true
            LIMIT 1
        ];
        if (!rtList.isEmpty()) return rtList[0].Id;

        // Fallback: first active non-person account RT
        List<RecordType> fallback = [
            SELECT Id FROM RecordType
            WHERE SObjectType  = 'Account'
            AND   IsPersonType = false
            AND   IsActive     = true
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0].Id;
    }


    // ── Wrapper Classes ──────────────────────────────────────────────────────

    public class LeadConvertWrapper {
        @AuraEnabled public Lead               lead              { get; set; }
        @AuraEnabled public Id                 accountId         { get; set; }
        @AuraEnabled public String             accountName       { get; set; }
        @AuraEnabled public Id                 contactId         { get; set; }
        @AuraEnabled public String             contactName       { get; set; }
        @AuraEnabled public String             opportunityName   { get; set; }
        @AuraEnabled public String             oppRecordTypeName { get; set; }
        @AuraEnabled public List<StatusOption> convertedStatuses { get; set; }
    }

    public class StatusOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        public StatusOption(String l, String v) { label = l; value = v; }
    }

    public class ConversionResult {
        @AuraEnabled public Boolean success       { get; set; }
        @AuraEnabled public String  message       { get; set; }
        @AuraEnabled public Id      accountId     { get; set; }
        @AuraEnabled public Id      contactId     { get; set; }
        @AuraEnabled public Id      opportunityId { get; set; }
    }
}