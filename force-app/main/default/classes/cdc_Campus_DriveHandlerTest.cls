@isTest
public class cdc_Campus_DriveHandlerTest {

    @isTest
    static void testBeforeInsertNameFormatting() {
        // Create an Account
        Account acc = new Account(Name = 'Test Academic Institution');
        insert acc;

        // Create Campus_Drive__c records to test different naming scenarios
        List<Campus_Drive__c> driveList = new List<Campus_Drive__c>();

        // Scenario 1: Both Academic Year and Account are provided
        Campus_Drive__c drive1 = new Campus_Drive__c(
            Account__c = acc.Id,
            Academic_Year__c = '2026'
        );
        driveList.add(drive1);

        // Scenario 2: Only Academic Year is provided
        Campus_Drive__c drive2 = new Campus_Drive__c(
            Academic_Year__c = '2027'
        );
        driveList.add(drive2);

        // Scenario 3: Only Account is provided
        Campus_Drive__c drive3 = new Campus_Drive__c(
            Account__c = acc.Id
        );
        driveList.add(drive3);

        // Scenario 4: Neither Academic Year nor Account is provided
        Campus_Drive__c drive4 = new Campus_Drive__c();
        driveList.add(drive4);

        Test.startTest();
        insert driveList;
        Test.stopTest();

        // Query inserted records and assert names
        Map<Id, Campus_Drive__c> driveMap = new Map<Id, Campus_Drive__c>([
            SELECT Id, Name, Account__c, Academic_Year__c 
            FROM Campus_Drive__c 
            WHERE Id IN :driveList
        ]);

        System.assertEquals('2026 - Test Academic Institution', driveMap.get(drive1.Id).Name, 'Name should be format: Academic Year - Account Name');
        System.assertEquals('2027', driveMap.get(drive2.Id).Name, 'Name should be academic year only');
        System.assertEquals('Test Academic Institution', driveMap.get(drive3.Id).Name, 'Name should be account name only');
        System.assertEquals('Campus Drive', driveMap.get(drive4.Id).Name, 'Name should default to Campus Drive');
    }

    @isTest
    static void testAfterInsertAccountAggregationSingle() {
        // Create Account
        Account acc = new Account(Name = 'Single Drive Account');
        insert acc;

        // Insert one visited campus drive
        Campus_Drive__c drive = new Campus_Drive__c(
            Account__c = acc.Id,
            Academic_Year__c = '2024',
            Visited__c = true
        );

        Test.startTest();
        insert drive;
        Test.stopTest();

        // Verify account values are aggregated correctly
        Account updatedAcc = [
            SELECT Id, Total_Visit__c, Status_According_to_Current_Year__c, Recent_Association__c 
            FROM Account 
            WHERE Id = :acc.Id
        ];
        System.assertEquals(1, updatedAcc.Total_Visit__c, 'Total visit should be 1');
        System.assertEquals('New', updatedAcc.Status_According_to_Current_Year__c, 'Status should be New');
        System.assertEquals('2024', updatedAcc.Recent_Association__c, 'Recent association should be 2024');
    }

    @isTest
    static void testAfterInsertAccountAggregationMultiple() {
        // Create Account
        Account acc = new Account(Name = 'Multiple Drive Account');
        insert acc;

        // Insert multiple campus drives
        List<Campus_Drive__c> driveList = new List<Campus_Drive__c>{
            new Campus_Drive__c(
                Account__c = acc.Id,
                Academic_Year__c = '2025',
                Visited__c = true
            ),
            new Campus_Drive__c(
                Account__c = acc.Id,
                Academic_Year__c = '2026',
                Visited__c = true
            ),
            new Campus_Drive__c(
                Account__c = acc.Id,
                Academic_Year__c = '2023',
                Visited__c = false // should not increment visited count
            )
        };

        Test.startTest();
        insert driveList;
        Test.stopTest();

        // Verify account values are aggregated correctly
        Account updatedAcc = [
            SELECT Id, Total_Visit__c, Status_According_to_Current_Year__c, Recent_Association__c 
            FROM Account 
            WHERE Id = :acc.Id
        ];
        System.assertEquals(2, updatedAcc.Total_Visit__c, 'Total visit should be 2');
        System.assertEquals('Repeat', updatedAcc.Status_According_to_Current_Year__c, 'Status should be Repeat');
        System.assertEquals('2026', updatedAcc.Recent_Association__c, 'Recent association should be the max year (2026)');
    }
}