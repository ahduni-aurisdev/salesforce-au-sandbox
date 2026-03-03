@isTest
public class WalkinLeadControllerTest {

    // Create required reference data (Country__c)
    static Country__c createCountry() {
        Country__c c = new Country__c(
            Name = 'India',
            Status__c = 'Active',
            Country_Code__c = 'IN'
        );
        insert c;
        return c;
    }

    @isTest
    static void testCreateWalkinLead() {

        // CREATE required lookup first
        Country__c country = createCountry();

        // Build JSON similar to LWC payload
        String jsonBody = JSON.serialize(new Map<String, Object>{
            'firstName'              => 'John',
            'lastName'               => 'Doe',
            'email'                  => 'john.doe@gmail.com',
            'mobile'                 => '9876543210',
            'city'                   => 'Ahmedabad',
            'state'                  => 'Gujarat',
            'company'                => 'Individual',
            'programmesOfInterest'   => 'Master of Business Administration',
            'ugDegree'               => 'BBA',
            'ugUniversity'           => 'AU',
            'entranceExams'          => 'GMAT',
            'howDidYouHear'          => 'Online Search',
            'formDate'               => '2025-01-01'
        });

        Test.startTest();
        Id leadId = WalkinLeadController.createWalkinLead(jsonBody);
        Test.stopTest();

        System.assertNotEquals(null, leadId, 'Lead must be created');

        // ***************************************************
        // ADDING YOUR DEBUG QUERY HERE
        // ***************************************************
        Lead debugLead = [
            SELECT Id, FirstName, LastName, Email, Phone
            FROM Lead
            WHERE Email = 'john.doe@gmail.com'
        ];
        System.debug('DEBUG LEAD FROM TEST: ' + debugLead);
        // ***************************************************

        Lead insertedLead = [
            SELECT FirstName, LastName, Email, Phone, City, State,
                   Preferred_Programme__c, Undergraduate_Degree_Name__c,
                   Name_of_University_College__c, Entrance_Test__c,
                   How_did_you_come_to_know_about_AU__c,
                   Submission_Channel__c, Form_Submission_Date__c,
                   LeadSource, Department__c, TypeOfForm__c,
                   Country__c
            FROM Lead WHERE Id = :leadId
        ];

        System.assertEquals('John', insertedLead.FirstName);
        System.assertEquals('Doe', insertedLead.LastName);
        System.assertEquals('john.doe@gmail.com', insertedLead.Email);
        System.assert(insertedLead.Phone.endsWith('9876543210'),
              'Phone number should end with digits entered by user.');
        System.assertEquals('Ahmedabad', insertedLead.City);
        System.assertEquals('Gujarat', insertedLead.State);
        System.assertEquals('Master of Business Administration', insertedLead.Preferred_Programme__c);
        System.assertEquals('BBA', insertedLead.Undergraduate_Degree_Name__c);
        System.assertEquals('AU', insertedLead.Name_of_University_College__c);
        System.assertEquals('GMAT', insertedLead.Entrance_Test__c);
        System.assertEquals('Online Search', insertedLead.How_did_you_come_to_know_about_AU__c);
        System.assertEquals('Experience Form', insertedLead.Submission_Channel__c);
        System.assertEquals('Walk-in', insertedLead.LeadSource);
        System.assertEquals('Masters', insertedLead.Department__c);
        System.assertEquals('AMSOM_WalkIn', insertedLead.TypeOfForm__c);
        System.assertEquals(country.Id, insertedLead.Country__c);
    }


    // Test Duplicate Email Scenario
    @isTest
    static void testDuplicateEmailReturnsSameLead() {

        Country__c country = createCountry();

        // Insert an existing lead
        Lead existing = new Lead(
            FirstName = 'Old',
            LastName = 'Test',
            Email = 'dup@gmail.com',
            Company = 'Test Co'
        );
        insert existing;

        String jsonBody = JSON.serialize(new Map<String, Object>{
            'firstName'              => 'New',
            'lastName'               => 'User',
            'email'                  => 'dup@gmail.com',
            'mobile'                 => '9876543000',
            'city'                   => 'City',
            'state'                  => 'State',
            'company'                => 'Individual',
            'programmesOfInterest'   => 'Master of Business Administration',
            'ugDegree'               => 'BBA',
            'ugUniversity'           => 'AU',
            'entranceExams'          => 'GMAT',
            'howDidYouHear'          => 'Online Search',
            'formDate'               => '2025-01-01'
        });

        Test.startTest();
        Id returnedId = WalkinLeadController.createWalkinLead(jsonBody);
        Test.stopTest();

        System.assertEquals(existing.Id, returnedId, 'Duplicate email must return same lead');
    }
}