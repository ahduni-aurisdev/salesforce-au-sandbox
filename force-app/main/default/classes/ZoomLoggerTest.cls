/**
 * @description Tests for ZoomLogger.
 * @author AU Development Team
 * @date 2026-11-02
 * @version 1.0
 * @lastModified 2026-11-02
 */
@IsTest
private class ZoomLoggerTest {
    private static final String LOG_NAME = 'ZoomLoggerTest';

    @IsTest
    static void logsExceptionWithContext() {
        Test.startTest();
        ZoomLogger.logFailure(LOG_NAME, 'ZoomLoggerTest', '123456789', new DmlException('boom'));
        Test.stopTest();

        API_Log__c log = [
            SELECT Log_Name__c, Apex_Class_Name__c, Registration_Number__c, Log_Type__c, Response__c
            FROM API_Log__c
            WHERE Log_Name__c = :LOG_NAME
        ];
        System.assertEquals('123456789', log.Registration_Number__c, 'The Zoom reference must be stored');
        System.assertEquals(ZoomLogger.LOG_TYPE_FAILED, log.Log_Type__c, 'Failures must be logged with type Failed');
        System.assert(log.Response__c.contains('System.DmlException: boom'), 'The exception type and message must be stored');
    }

    @IsTest
    static void truncatesLongValuesAndAcceptsNullError() {
        String longReference = 'x'.repeat(300);
        Test.startTest();
        ZoomLogger.logFailure(LOG_NAME, null, longReference, (Exception) null);
        Test.stopTest();

        API_Log__c log = [SELECT Registration_Number__c, Response__c FROM API_Log__c WHERE Log_Name__c = :LOG_NAME];
        System.assertEquals(255, log.Registration_Number__c.length(), 'Text values must be truncated to 255 characters');
        System.assertEquals(null, log.Response__c, 'A null error must produce an empty message');
    }
}