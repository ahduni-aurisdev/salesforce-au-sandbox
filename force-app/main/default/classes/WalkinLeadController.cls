public without sharing class WalkinLeadController {

    @AuraEnabled(cacheable=false)
    public static Id createWalkinLead(String reqJson) {
        System.debug('RAW JSON from LWC: ' + reqJson);

        // Deserialize JSON manually
        WalkinLeadRequest req = (WalkinLeadRequest) JSON.deserialize(reqJson, WalkinLeadRequest.class);
        System.debug('Deserialized Email = ' + req.email);
        System.debug('Deserialized Mobile = ' + req.mobile);

        if (!String.isBlank(req.email)) {
            List<Lead> existing = [SELECT Id FROM Lead WHERE Email = :req.email LIMIT 1];
            if (!existing.isEmpty()) {
                return existing[0].Id;
            }
        }

        Lead l = new Lead();
        l.LastName = String.isBlank(req.lastName) ? 'Unknown' : req.lastName;
        l.FirstName = req.firstName;
        l.Email = req.email;

        if (!String.isBlank(req.mobile)) {
            l.Phone = req.mobile.replaceAll('[^0-9]', '');
        }

        l.City = req.city;
        l.State = req.state;

        List<Country__c> countryRec = [
            SELECT Id, Name
            FROM Country__c
            WHERE Name = 'India'
            AND Status__c = 'Active'
            LIMIT 1
        ];
        
        if(!countryRec.isEmpty()){
           l.Country__c = countryRec[0].Id;
        }    

        l.Company = String.isBlank(req.company) ? 'Individual' : req.company;

        if (req.programmesOfInterest == 'Master of Business Administration') {
            l.Preferred_Programme__c = 'Master of Business Administration';
        } else if (req.programmesOfInterest == 'Master of Science in Economics') {
            l.Preferred_Programme__c = 'Master of Science in Economics';
        } else if (req.programmesOfInterest == 'Master of Science in Quantitative Finance') {
            l.Preferred_Programme__c = 'Master of Science in Quantitative Finance';
        } else if (req.programmesOfInterest == 'MMS Heritage Management' ||
                   req.programmesOfInterest == 'Masters of Management Studies in Heritage Management') {
            l.Preferred_Programme__c = 'Master of Management Studies in Heritage Management';
        }

        l.Undergraduate_Degree_Name__c = req.ugDegree;
        l.Name_of_University_College__c = req.ugUniversity;
        l.Entrance_Test__c = req.entranceExams;
        l.How_did_you_come_to_know_about_AU__c = req.howDidYouHear;
        l.Submission_Channel__c = 'Experience Form';
        l.Form_Submission_Date__c = Datetime.now();
        l.LeadSource = 'Walk-in';
        l.Department__c = 'Masters';
        l.TypeOfForm__c = 'AMSOM_WalkIn';

        System.debug('=== DEBUG START ===');
        System.debug('REQ.MOBILE = ' + req.mobile);
        System.debug('CLEANED PHONE = ' + l.Phone);
        System.debug('REQ.EMAIL = ' + req.email);
        System.debug('LEAD.COUNTRY__C = ' + l.Country__c);
        System.debug('=== DEBUG END ===');

        try {
            insert l;
            System.debug('Lead created successfully. ID: ' + l.Id);
            return l.Id;
        } catch (DmlException dmlex) {
            System.debug('DML Exception: ' + dmlex.getMessage());
            throw new AuraHandledException('Error creating lead: ' + dmlex.getMessage());
        }
    }

    
    public class WalkinLeadRequest {
        public String firstName;
        public String lastName;
        public String email;
        public String mobile;
        public String city;
        public String state;
        public String company;
        public String programmesOfInterest;
        public String ugDegree;
        public String ugUniversity;
        public String entranceExams;
        public String howDidYouHear;
        public String formDate;
    }
}