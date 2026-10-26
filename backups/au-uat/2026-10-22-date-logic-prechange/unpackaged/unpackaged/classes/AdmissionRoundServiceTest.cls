/**
 * @description Tests validation, bulk upsert, partial success, and logging for admission rounds.
 * @author AU Development Team
 * @date 2026-10-16
 * @version 1.1
 * @lastModified 2026-10-19
 */
@IsTest
private class AdmissionRoundServiceTest {
    @TestSetup
    static void createData() {
        List<Admission_Round__c> rounds = new List<Admission_Round__c>();
        for (Integer index = 0; index < 200; index++) {
            rounds.add(new Admission_Round__c(
                Name = 'Service Setup ' + index,
                Round_Code__c = 'SERVICE-' + index,
                Is_Active__c = true
            ));
        }
        insert rounds;
    }

    @IsTest
    static void shouldInsertAndUpdateInOneBulkOperation() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('SERVICE-0', 'Updated Existing Round', '2027-28', 'B.Tech', '2027-01-01', '2027-02-01', false),
            request('SERVICE-NEW', 'New Round', '2027-28', 'MBA', '2027-03-01', '2027-04-01', null)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-SUCCESS');
        Test.stopTest();

        System.assertEquals(true, response.success, 'The mixed insert/update request should succeed.');
        System.assertEquals(2, response.successCount, 'Both records should succeed.');
        System.assertEquals('UPDATED', response.results[0].action, 'The existing record should be updated.');
        System.assertEquals('INSERTED', response.results[1].action, 'The new record should be inserted.');

        Map<String, Admission_Round__c> savedByCode = new Map<String, Admission_Round__c>();
        for (Admission_Round__c saved : [
            SELECT Name, Round_Code__c, Is_Active__c
            FROM Admission_Round__c
            WHERE Round_Code__c IN ('SERVICE-0', 'SERVICE-NEW')
        ]) {
            savedByCode.put(saved.Round_Code__c, saved);
        }
        System.assertEquals(
            'Updated Existing Round',
            savedByCode.get('SERVICE-0').Name,
            'The existing record should contain the updated name.'
        );
        System.assertEquals(false, savedByCode.get('SERVICE-0').Is_Active__c, 'Active should be updated to false.');
        System.assertEquals(true, savedByCode.get('SERVICE-NEW').Is_Active__c, 'New records should default active.');
    }

    @IsTest
    static void shouldReturnExactValidationErrorsAndLogFailures() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            request('DUPLICATE', 'First', null, null, null, null, true),
            request('DUPLICATE', 'Second', null, null, null, null, true),
            request('INVALID-DATE', 'Invalid Date', null, null, '2027-04-02', '2027-04-01', true),
            requestWithDepartment('INVALID-DEPARTMENT', 'Invalid Department', 'Unknown Department'),
            request('VALID-PARTIAL', 'Valid Partial', '2027-28', null, null, null, true)
        };


        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-PARTIAL');
        Test.stopTest();

        System.assertEquals(false, response.success, 'A partial-success request should not be marked fully successful.');
        System.assertEquals(1, response.successCount, 'Only the valid record should succeed.');
        System.assertEquals(4, response.failureCount, 'Four invalid records should fail.');
        System.assert(
            response.results[0].errors[0].contains('more than once'),
            'Duplicate round codes should return an exact validation message.'
        );
        System.assert(
            response.results[2].errors[0].contains('on or before'),
            'Invalid date order should return an exact validation message.'
        );
        System.assert(
            response.results[3].errors[0].contains('department must be one of'),
            'An unsupported department should return the allowed-values error.'
        );
        System.assertEquals(
            4,
            [SELECT COUNT() FROM API_Log__c WHERE Log_Name__c = 'AdmissionRoundUpsert'],
            'Every failed record should create an API log entry.'
        );
    }

    @IsTest
    static void shouldProcessTwoHundredRecords() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 200; index++) {
            requestEnvelope.records.add(
                request('BULK-' + index, 'Bulk Round ' + index, '2028-29', 'Program ' + index, null, null, true)
            );
        }

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-BULK');
        Test.stopTest();

        System.assertEquals(200, response.successCount, 'All 200 bulk records should be processed.');
        System.assertEquals(
            200,
            [SELECT COUNT() FROM Admission_Round__c WHERE Round_Code__c LIKE 'BULK-%'],
            'The API should insert all 200 admission rounds.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Admission_Round__c
                WHERE Round_Code__c LIKE 'BULK-%' AND Is_Active__c = true
            ],
            'Only the final record for the shared department and admission year should remain active.'
        );
    }

    @IsTest
    static void shouldDeactivateExistingRoundForSameGroup() {
        insert new Admission_Round__c(
            Name = 'Previous Active Round',
            Round_Code__c = 'SINGLE-OLD',
            Admission_Year__c = '2030-31',
            Department__c = 'Masters',
            Is_Active__c = true
        );
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            requestWithGroup('SINGLE-NEW', 'New Active Round', '2030-31', 'Masters', true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SINGLE-EXISTING');
        Test.stopTest();

        System.assertEquals(true, response.success, 'The replacement active round should succeed.');
        Map<String, Admission_Round__c> savedByCode = queryRoundsByCode(
            new Set<String>{'SINGLE-OLD', 'SINGLE-NEW'}
        );
        System.assertEquals(false, savedByCode.get('SINGLE-OLD').Is_Active__c, 'The previous round must be inactive.');
        System.assertEquals(true, savedByCode.get('SINGLE-NEW').Is_Active__c, 'The new round must be active.');
    }

    @IsTest
    static void shouldKeepLastMatchingPayloadRecordActive() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            requestWithGroup('ORDER-1', 'First Round', '2031-32', 'Graduation', true),
            requestWithGroup('ORDER-2', 'Second Round', '2031-32', 'Graduation', true),
            requestWithGroup('ORDER-3', 'Final Round', '2031-32', 'Graduation', true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SINGLE-ORDER');
        Test.stopTest();

        System.assertEquals(3, response.successCount, 'Every sequential payload record should be processed.');
        Map<String, Admission_Round__c> savedByCode = queryRoundsByCode(
            new Set<String>{'ORDER-1', 'ORDER-2', 'ORDER-3'}
        );
        System.assertEquals(false, savedByCode.get('ORDER-1').Is_Active__c, 'The first record must be inactive.');
        System.assertEquals(false, savedByCode.get('ORDER-2').Is_Active__c, 'The second record must be inactive.');
        System.assertEquals(true, savedByCode.get('ORDER-3').Is_Active__c, 'The final record must remain active.');
    }

    @IsTest
    static void shouldRequireDepartmentAndAdmissionYearForActiveRound() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        AdmissionRoundApiModels.AdmissionRoundRequest missingDepartment =
            requestWithGroup('MISSING-DEPT', 'Missing Department', '2032-33', null, true);
        AdmissionRoundApiModels.AdmissionRoundRequest missingYear =
            requestWithGroup('MISSING-YEAR', 'Missing Year', null, 'Phd', true);
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            missingDepartment,
            missingYear
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SINGLE-REQUIRED');
        Test.stopTest();

        System.assertEquals(0, response.successCount, 'Neither invalid active round should be saved.');
        System.assertEquals(2, response.failureCount, 'Both missing grouping values should fail.');
        System.assertEquals(
            'department is required when isActive is true.',
            response.results[0].errors[0],
            'The missing Department error must be exact.'
        );
        System.assertEquals(
            'admissionYear is required when isActive is true.',
            response.results[1].errors[0],
            'The missing Admission Year error must be exact.'
        );
    }

    @IsTest
    static void shouldNotDeactivateCurrentRoundForInactiveInput() {
        insert new Admission_Round__c(
            Name = 'Current Active Round',
            Round_Code__c = 'INACTIVE-CURRENT',
            Admission_Year__c = '2033-34',
            Department__c = 'Undergraduation',
            Is_Active__c = true
        );
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            requestWithGroup('INACTIVE-NEW', 'Inactive New Round', '2033-34', 'Undergraduation', false)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-SINGLE-INACTIVE');
        Test.stopTest();

        System.assertEquals(true, response.success, 'The explicitly inactive record should succeed.');
        Map<String, Admission_Round__c> savedByCode = queryRoundsByCode(
            new Set<String>{'INACTIVE-CURRENT', 'INACTIVE-NEW'}
        );
        System.assertEquals(true, savedByCode.get('INACTIVE-CURRENT').Is_Active__c, 'The current round must stay active.');
        System.assertEquals(false, savedByCode.get('INACTIVE-NEW').Is_Active__c, 'The new round must stay inactive.');
    }

    @IsTest
    static void shouldKeepDifferentGroupsIndependentlyActive() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            requestWithGroup('GROUP-MASTERS', 'Masters Round', '2034-35', 'Masters', true),
            requestWithGroup('GROUP-PHD', 'Phd Round', '2034-35', 'Phd', true),
            requestWithGroup('GROUP-NEXT-YEAR', 'Next Year Round', '2035-36', 'Masters', true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-INDEPENDENT-GROUPS');
        Test.stopTest();

        System.assertEquals(3, response.successCount, 'All independent groups should succeed.');
        System.assertEquals(
            3,
            [
                SELECT COUNT()
                FROM Admission_Round__c
                WHERE Round_Code__c IN ('GROUP-MASTERS', 'GROUP-PHD', 'GROUP-NEXT-YEAR')
                    AND Is_Active__c = true
            ],
            'Different Department and Admission Year combinations should remain active independently.'
        );
    }

    @IsTest
    static void shouldApplyRuleWhenExistingRoundMovesGroups() {
        insert new List<Admission_Round__c>{
            new Admission_Round__c(
                Name = 'Moving Round',
                Round_Code__c = 'MOVE-SOURCE',
                Admission_Year__c = '2036-37',
                Department__c = 'Graduation',
                Is_Active__c = true
            ),
            new Admission_Round__c(
                Name = 'Target Group Active',
                Round_Code__c = 'MOVE-TARGET',
                Admission_Year__c = '2037-38',
                Department__c = 'Executive Education',
                Is_Active__c = true
            )
        };
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>{
            requestWithGroup('MOVE-SOURCE', 'Moved Round', '2037-38', 'Executive Education', true)
        };

        Test.startTest();
        AdmissionRoundApiModels.ResponseEnvelope response =
            AdmissionRoundService.process(requestEnvelope, 'REQ-MOVE-GROUP');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Moving the round should succeed.');
        Map<String, Admission_Round__c> savedByCode = queryRoundsByCode(
            new Set<String>{'MOVE-SOURCE', 'MOVE-TARGET'}
        );
        System.assertEquals(true, savedByCode.get('MOVE-SOURCE').Is_Active__c, 'The moved round must stay active.');
        System.assertEquals(false, savedByCode.get('MOVE-TARGET').Is_Active__c, 'The target group round must deactivate.');
    }

    @IsTest
    static void shouldRejectMoreThanTwoHundredRecords() {
        AdmissionRoundApiModels.RequestEnvelope requestEnvelope = new AdmissionRoundApiModels.RequestEnvelope();
        requestEnvelope.records = new List<AdmissionRoundApiModels.AdmissionRoundRequest>();
        for (Integer index = 0; index < 201; index++) {
            requestEnvelope.records.add(request('LIMIT-' + index, 'Limit ' + index, null, null, null, null, true));
        }

        try {
            AdmissionRoundService.process(requestEnvelope, 'REQ-SERVICE-LIMIT');
            System.assert(false, 'A request containing 201 records must throw an API exception.');
        } catch (AdmissionRoundService.AdmissionRoundApiException exceptionValue) {
            System.assertEquals(
                'A maximum of 200 admission rounds is allowed per request.',
                exceptionValue.getMessage(),
                'The limit error should be explicit.'
            );
        }
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest request(
        String roundCode,
        String roundName,
        String admissionYear,
        String program,
        String startDate,
        String endDate,
        Boolean isActive
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input = new AdmissionRoundApiModels.AdmissionRoundRequest();
        input.roundCode = roundCode;
        input.roundName = roundName;
        input.admissionYear = admissionYear;
        input.department = 'CLeF';
        input.program = program;
        input.startDate = startDate;
        input.endDate = endDate;
        input.isActive = isActive;
        return input;
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest requestWithDepartment(
        String roundCode,
        String roundName,
        String department
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input =
            request(roundCode, roundName, null, null, null, null, true);
        input.department = department;
        return input;
    }

    private static AdmissionRoundApiModels.AdmissionRoundRequest requestWithGroup(
        String roundCode,
        String roundName,
        String admissionYear,
        String department,
        Boolean isActive
    ) {
        AdmissionRoundApiModels.AdmissionRoundRequest input =
            request(roundCode, roundName, admissionYear, null, null, null, isActive);
        input.department = department;
        return input;
    }

    private static Map<String, Admission_Round__c> queryRoundsByCode(Set<String> roundCodes) {
        Map<String, Admission_Round__c> recordsByCode = new Map<String, Admission_Round__c>();
        for (Admission_Round__c recordValue : [
            SELECT Round_Code__c, Is_Active__c
            FROM Admission_Round__c
            WHERE Round_Code__c IN :roundCodes
        ]) {
            recordsByCode.put(recordValue.Round_Code__c, recordValue);
        }
        return recordsByCode;
    }
}