public without sharing class OpportunityTriggerHandler {

    private static final String CDC_RECORD_TYPE_DEV_NAME = 'CDC';
    private static final Set<String> CAMPUS_DRIVE_STAGES = new Set<String>{ 'Completed', 'Closed Won' };

    public static void handleBeforeUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppsMap) {
        setCompletionDate(newOpps, oldOppsMap);
    }

    public static void handleAfterUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppsMap) {
        List<Opportunity> targetOpps = filterOpps(newOpps, oldOppsMap);
        if (!targetOpps.isEmpty()) {
            upsertCampusDrives(targetOpps);
        }
    }

    private static void setCompletionDate(List<Opportunity> newOpps, Map<Id, Opportunity> oldOppsMap) {
        Id cdcRecordTypeId = getCdcRecordTypeId();
        if (cdcRecordTypeId == null) return;
        for (Opportunity opp : newOpps) {
            if (opp.RecordTypeId != cdcRecordTypeId) continue;
            Opportunity oldOpp = oldOppsMap.get(opp.Id);
            if (opp.StageName == 'Completed' && (oldOpp == null || oldOpp.StageName != 'Completed')) {
                opp.Completion_Date__c = Date.today();
            }
        }
    }

    private static List<Opportunity> filterOpps(List<Opportunity> opps, Map<Id, Opportunity> oldOppsMap) {
        List<Opportunity> filtered = new List<Opportunity>();
        Id cdcRecordTypeId = getCdcRecordTypeId();
        if (cdcRecordTypeId == null) return filtered;
        for (Opportunity opp : opps) {
            if (opp.RecordTypeId != cdcRecordTypeId) continue;
            Opportunity oldOpp = oldOppsMap.get(opp.Id);
            Boolean stageChangedToCampusDriveStage =
                oldOpp != null &&
                oldOpp.StageName != opp.StageName &&
                CAMPUS_DRIVE_STAGES.contains(opp.StageName);
            if (stageChangedToCampusDriveStage) filtered.add(opp);
        }
        return filtered;
    }

    private static void upsertCampusDrives(List<Opportunity> opportunities) {
        Set<Id>     accountIds    = new Set<Id>();
        Set<String> academicYears = new Set<String>();
        for (Opportunity opp : opportunities) {
            if (opp.AccountId != null)              accountIds.add(opp.AccountId);
            if (String.isNotBlank(opp.Academic_Year__c)) academicYears.add(opp.Academic_Year__c);
        }
        if (accountIds.isEmpty() || academicYears.isEmpty()) return;

        Id cdcRecordTypeId = getCdcRecordTypeId();
        if (cdcRecordTypeId == null) return;

        // Re-query ALL Completed/Closed Won CDC opps for those Account+Year combos
        // to recalculate from scratch and avoid double-counting.
        List<Opportunity> allRelevantOpps = [
            SELECT AccountId, Academic_Year__c, Program__c,
                   Total_Expected_Students__c,
                   Total_Registered_Students__c,
                   Total_Appeared_Students__c,
                   Total_Shortlisted_Students__c,
                   Total_Selected_Students__c,
                   Total_Offer_Accepted__c,
                   Max_CTC_Offered__c
            FROM Opportunity
            WHERE AccountId IN :accountIds
              AND Academic_Year__c IN :academicYears
              AND StageName IN :CAMPUS_DRIVE_STAGES
              AND RecordTypeId = :cdcRecordTypeId
        ];

        // Aggregate totals per Account + Academic Year
        Map<String, DriveAggregate> aggregateMap = new Map<String, DriveAggregate>();
        for (Opportunity opp : allRelevantOpps) {
            if (opp.AccountId == null || String.isBlank(opp.Academic_Year__c)) continue;
            String key = opp.AccountId + '_' + opp.Academic_Year__c;
            if (!aggregateMap.containsKey(key)) {
                aggregateMap.put(key, new DriveAggregate(opp.AccountId, opp.Academic_Year__c));
            }
            DriveAggregate agg = aggregateMap.get(key);
            agg.expected    += opp.Total_Expected_Students__c    != null ? opp.Total_Expected_Students__c    : 0;
            agg.registered  += opp.Total_Registered_Students__c  != null ? opp.Total_Registered_Students__c  : 0;
            agg.appeared    += opp.Total_Appeared_Students__c     != null ? opp.Total_Appeared_Students__c     : 0;
            agg.shortlisted += opp.Total_Shortlisted_Students__c  != null ? opp.Total_Shortlisted_Students__c  : 0;
            agg.selected    += opp.Total_Selected_Students__c     != null ? opp.Total_Selected_Students__c     : 0;
            agg.offerCount  += opp.Total_Offer_Accepted__c        != null ? opp.Total_Offer_Accepted__c        : 0;
            if (opp.Max_CTC_Offered__c != null && opp.Max_CTC_Offered__c > agg.maxCtc) {
                agg.maxCtc = opp.Max_CTC_Offered__c;
            }
            if (String.isNotBlank(opp.Program__c)) {
                agg.programs.addAll(opp.Program__c.split(';'));
            }
        }
        if (aggregateMap.isEmpty()) return;

        // Look up existing Campus Drive records by External_Id__c
        Map<String, Id> existingIdByKey = new Map<String, Id>();
        for (Campus_Drive__c cd : [
            SELECT Id, External_Id__c
            FROM Campus_Drive__c
            WHERE External_Id__c IN :aggregateMap.keySet()
        ]) {
            existingIdByKey.put(cd.External_Id__c, cd.Id);
        }

        // Build insert and update lists
        List<Campus_Drive__c> toInsert = new List<Campus_Drive__c>();
        List<Campus_Drive__c> toUpdate = new List<Campus_Drive__c>();

        for (String key : aggregateMap.keySet()) {
            DriveAggregate  agg = aggregateMap.get(key);
            Campus_Drive__c cd  = new Campus_Drive__c();

            if (existingIdByKey.containsKey(key)) {
                cd.Id = existingIdByKey.get(key);
            }

            // Field mapping: Opportunity totals → Campus Drive fields
            cd.Account__c       = agg.accountId;
            cd.Academic_Year__c = agg.academicYear;
            cd.External_Id__c   = key;
            cd.Expected__c      = agg.expected;      // Total_Expected_Students__c
            cd.Registered__c    = agg.registered;    // Total_Registered_Students__c
            cd.Appeared__c      = agg.appeared;      // Total_Appeared_Students__c
            cd.Shortlisted__c   = agg.shortlisted;   // Total_Shortlisted_Students__c
            cd.Selected__c      = agg.selected;      // Total_Selected_Students__c
            cd.Offer_Count__c   = agg.offerCount;    // Total_Offer_Accepted__c
            cd.CTC__c           = agg.maxCtc > 0 ? agg.maxCtc : null; // Max_CTC_Offered__c
            cd.Program__c       = agg.programs.isEmpty()
                                    ? null
                                    : String.join(new List<String>(agg.programs), ';');
            cd.Visited__c       = true;

            if (cd.Id != null) {
                toUpdate.add(cd);
            } else {
                toInsert.add(cd);
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private static Id getCdcRecordTypeId() {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(CDC_RECORD_TYPE_DEV_NAME)
            ?.getRecordTypeId();
    }

    private class DriveAggregate {
        Id      accountId;
        String  academicYear;
        Decimal expected    = 0;
        Decimal registered  = 0;
        Decimal appeared    = 0;
        Decimal shortlisted = 0;
        Decimal selected    = 0;
        Decimal offerCount  = 0;
        Decimal maxCtc      = 0;
        Set<String> programs = new Set<String>();
        DriveAggregate(Id accId, String year) {
            accountId    = accId;
            academicYear = year;
        }
    }
}