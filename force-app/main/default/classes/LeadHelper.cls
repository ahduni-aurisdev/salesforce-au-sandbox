/**
* @description
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Developer Name   : Preksha Chauhan
* Created Date     : 07/18/2024
* Class Name       : LeadHelper
* Description      : This class provides methods for managing Lead assignments based 
*                    on specific criteria, including round-robin assignment for Masters 
*                    leads and direct assignment for PhD leads. It utilizes custom metadata 
*                    to determine assignmentroundRobinRules and keeps track of the last assigned 
*                    user to maintain even distribution. The class also includes a method 
*                    to retrieve record types and a static map of country dialing codes 
*                    for phone number management.
**********************************************************************************************/
public without sharing class LeadHelper {
    /**
    * @description assign user to master leads
    * @param leads list of leads
    */
    public static void leadAssignmentForMastersByCourse(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            System.debug('⚠️ No leads provided for assignment.');
            return;
        }
    
        try {
            // Step 1: Load metadata (Course → Users)
            Map<String, List<Id>> courseToUsers = new Map<String, List<Id>>();
            Set<String> allEmails = new Set<String>();
    
            List<LeadAssignmentRule__mdt> metaRecords = [
                SELECT Label, Course__c, User_Email__c, Department__c
                FROM LeadAssignmentRule__mdt
            ];
            System.debug('📌 Loaded metadata records: ' + metaRecords.size());
    
            // Collect all emails
            for (LeadAssignmentRule__mdt record : metaRecords) {
                if (String.isNotBlank(record.User_Email__c)) {
                    for (String emailStr : record.User_Email__c.split(',')) {
                        if (String.isNotBlank(emailStr)) {
                            allEmails.add(emailStr.trim().toLowerCase());
                        }
                    }
                }
            }
            System.debug('📌 Collected emails: ' + allEmails);
    
            // Query Users
            Map<String, Id> emailToUserId = new Map<String, Id>();
            for (User u : [
                SELECT Id, Email FROM User WHERE Email IN :allEmails
            ]) {
                emailToUserId.put(u.Email.toLowerCase(), u.Id);
            }
            System.debug('📌 Email to UserId map: ' + emailToUserId);
    
            // Build Course → User IDs map
            for (LeadAssignmentRule__mdt record : metaRecords) {
                if (String.isNotBlank(record.User_Email__c)) {
                    List<Id> userList = new List<Id>();
                    for (String emailStr : record.User_Email__c.split(',')) {
                        Id uid = emailToUserId.get(emailStr.trim().toLowerCase());
                        if (uid != null) {
                            userList.add(uid);
                        } else {
                            System.debug('⚠️ No matching user found for email: ' + emailStr);
                        }
                    }
                    if (!userList.isEmpty()) {
                        String courseKey = record.Course__c.trim().toLowerCase();
                        courseToUsers.put(courseKey, userList);
                        System.debug('📌 Course: ' + courseKey + ' → Users: ' + userList);
                    }
                }
            }
    
            // Step 2: Load counters from Custom Setting
            Map<String, LeadAssignmentTrackerforOtherDept__c> counterMap = new Map<String, LeadAssignmentTrackerforOtherDept__c>();
            for (LeadAssignmentTrackerforOtherDept__c cs : [
                SELECT Course__c, Counter__c FROM LeadAssignmentTrackerforOtherDept__c
            ]) {
                counterMap.put(cs.Course__c.trim().toLowerCase(), cs);
            }
            System.debug('📌 Loaded counter map: ' + counterMap);
    
            // Step 3: Assignment + counter update
            Map<String, Integer> newCounterValues = new Map<String, Integer>();
    
            for (Lead lead : leads) {
                System.debug('➡️ Processing lead: ' + lead.Id + ' | Preferred_Programme__c: ' + lead.Preferred_Programme__c);
                if (String.isNotBlank(lead.Preferred_Programme__c)) {
                    String courseKey = lead.Preferred_Programme__c.trim().toLowerCase();
                    List<Id> users = courseToUsers.get(courseKey);
    
                    if (users != null && !users.isEmpty()) {
                        Integer userCount = users.size();
    
                        Integer currentIndex = counterMap.containsKey(courseKey)
                            ? Integer.valueOf(counterMap.get(courseKey).Counter__c)
                            : 0;
    
                        if (currentIndex >= userCount) {
                            currentIndex = 0;
                        }
    
                        lead.OwnerId = users[currentIndex];
                        System.debug('✅ Lead ' + lead.Id + ' assigned to UserId: ' + lead.OwnerId + ' (Index: ' + currentIndex + ')');
    
                        // Calculate next index
                        Integer nextIndex = (currentIndex + 1 < userCount) ? currentIndex + 1 : 0;
                        newCounterValues.put(courseKey, nextIndex);
                        System.debug('📌 Next counter for course ' + courseKey + ': ' + nextIndex);
                    } else {
                        System.debug('⚠️ No users found for course: ' + courseKey);
                    }
                } else {
                    System.debug('⚠️ Lead ' + lead.Id + ' has no Preferred_Programme__c');
                }
            }
    
            // Step 4: Save updated counters
            List<LeadAssignmentTrackerforOtherDept__c> counterUpdates = new List<LeadAssignmentTrackerforOtherDept__c>();
            for (String courseKey : newCounterValues.keySet()) {
                LeadAssignmentTrackerforOtherDept__c tracker = counterMap.get(courseKey);
                if (tracker == null) {
                    tracker = new LeadAssignmentTrackerforOtherDept__c(
                        Course__c = courseKey,
                        Name = courseKey
                    );
                    System.debug('📌 Creating new tracker for course: ' + courseKey);
                }
                tracker.Counter__c = newCounterValues.get(courseKey);
                counterUpdates.add(tracker);
            }
            System.debug('📌 Counter updates to save: ' + counterUpdates);
    
            if (!counterUpdates.isEmpty()) {
                try {
                    update counterUpdates;
                    System.debug('✅ Successfully updated counters.');
                } catch (DmlException dmle) {
                    System.debug('❌ Error updating counters: ' + dmle.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('❌ Error in leadAssignmentForMastersByCourse: ' + e.getMessage());
        }
    }
    
        
    
    /**
    * @description 
    * @param leads list of leads
     * Method Name     : assignLeadsByDepartment
     * Created By      : Preksha Chauhan
     * Created Date    : 10/11/2024
     * Description     : This method assigns leads to users based on the department (PhD or 
     *                   Executive Education) by retrieving user IDs from custom metadata.
     *                   For PhD leads, it assigns them to the 'Doctoral Admissions' user.
     *                   For Executive Education leads, it assigns them to 'Rahul Mehta'. 
     *                   The method uses custom metadata to map user names to user IDs and 
     *                   assigns the corresponding owner to each lead based on the record type.
    *******************************************************************************************/
    // public static void assignLeadsByDepartment(List<Lead> leads) {
    //     // Fetch user metadata for Doctoral Admissions and Executive Education
    //     Map<String, String> userAssignmentMap = new Map<String, String>();
    
    //     // Query custom metadata for PhD and Executive Education
    //     List<LeadAssignmentPhDUsers__mdt> userMetadata = [
    //         SELECT User_Id__c, User_Name__c 
    //         FROM LeadAssignmentPhDUsers__mdt 
    //         WHERE User_Name__c IN ('Doctoral Admissions', 'Rahul Mehta') 
            
    //     ];
    
    //     for (LeadAssignmentPhDUsers__mdt userMeta : userMetadata) {
    //         userAssignmentMap.put(userMeta.User_Name__c, userMeta.User_Id__c);
    //        // System.debug('189 --------   ' + userAssignmentMap.put(userMeta.User_Name__c, userMeta.User_Id__c));
    //     }
    
    //     // Assign leads based on their department (record type)
    //     for (Lead lead : leads) {
    //         String recordTypeName = getRecordTypeWithName().get(lead.RecordTypeId);
            
    //         if (recordTypeName == StaticValuesUtil.DEPARTMENT_PHD && userAssignmentMap.containsKey('Doctoral Admissions')) {
    //             lead.OwnerId = userAssignmentMap.get('Doctoral Admissions');
    //         } else if (recordTypeName == 'Executive Education' && userAssignmentMap.containsKey('Rahul Mehta')) {
    //             lead.OwnerId = userAssignmentMap.get('Rahul Mehta');
    //         } 
            
    //     }
    // }
    public static void assignLeadsByDepartment(List<Lead> leads) {
        if (leads.isEmpty()){
            return;
        } 
    
        // Map: Department -> User Email
        Map<String, String> deptToEmailMap = new Map<String, String>();
    
        // Query metadata
        for (LeadAssignmentPHD_Ex__mdt meta : [
            SELECT Department__c, User_Email__c
            FROM LeadAssignmentPHD_Ex__mdt
        ]) {
            deptToEmailMap.put(meta.Department__c, meta.User_Email__c);
        }
    
        // Collect all emails from metadata
        Set<String> userEmails = new Set<String>(deptToEmailMap.values());
    
        // Query Users by email
        Map<String, Id> emailToUserIdMap = new Map<String, Id>();
        for (User u : [
            SELECT Id, Email
            FROM User
            WHERE Email IN :userEmails
        ]) {
            emailToUserIdMap.put(u.Email, u.Id);
        }
    
        // Get RecordTypeId -> Name mapping
        Map<String, String> recordTypeMap = getRecordTypeWithName();
    
        // Assign leads dynamically
        for (Lead lead : leads) {
            String recordTypeName = recordTypeMap.get(lead.RecordTypeId);
    
            if (deptToEmailMap.containsKey(recordTypeName)) {
                String email = deptToEmailMap.get(recordTypeName);
                if (emailToUserIdMap.containsKey(email)) {
                    lead.OwnerId = emailToUserIdMap.get(email);
                }
            }
        }
    }
        
    /**
    * @description assign user to Undergraduation leads
    * @param leads list of leads
    */
   
    
    /** 
    * @description assign user to Undergraduation leads
    * @return map of record type with name 
    ****************************************************************************************
     * Method Name     : getRecordTypeWithName
     * Created By      : Preksha Chauhan
     * Created Date    : 07/18/2024
     * Description     : This method retrieves all record types and their corresponding 
     *                   names from the custom metadata. It returns a map with record type 
     *                   IDs as keys and their names as values.
    *******************************************************************************************/  
    public static Map<String,String> getRecordTypeWithName(){
        Map<String,String> recordTypeIdWithName = new Map<String,String>();
        List<Department_Record_Type_Mapping__mdt> recordTypeListMetadata = [SELECT Record_Type_Id__c , MasterLabel
                                                                            FROM Department_Record_Type_Mapping__mdt
                                                                            ]; 

        for(Department_Record_Type_Mapping__mdt singleRecord : recordTypeListMetadata){
            recordTypeIdWithName.put(singleRecord.Record_Type_Id__c,singleRecord.MasterLabel);
        }

        return recordTypeIdWithName;
    }

    /******************************************************************************************
     * Method Name     : countryCodeMap
     * Created By      : Preksha Chauhan
     * Created Date    : 07/18/2024
     * Description     : This static map stores the country dialing codes mapped to their 
     *                   respective ISO country codes. It is used to update the phone numbers 
     *                   of Lead records with the appropriate country dialing code.
    *******************************************************************************************/
    public static Map<String, String> countryCodeMap = new Map<String, String>{
        'AD' => '376',
       'AE' => '971',
       'AF' => '93',
       'AG' => '1-268',
       'AI' => '1-264',
       'AL' => '355',
       'AM' => '374',
       'AO' => '244',
       'AQ' => '672',
       'AR' => '54',
       'AT' => '43',
       'AU' => '61',
       'AW' => '297',
       'AX' => '358',
       'AZ' => '994',
       'BA' => '387',
       'BB' => '1-246',
       'BD' => '880',
       'BE' => '32',
       'BF' => '226',
       'BG' => '359',
       'BH' => '973',
       'BI' => '257',
       'BJ' => '229',
       'BL' => '590',
       'BM' => '1-441',
       'BN' => '673',
       'BO' => '591',
       'BQ' => '599',
       'BR' => '55',
       'BS' => '1-242',
       'BT' => '975',
       'BV' => '47',
       'BW' => '267',
       'BY' => '375',
       'BZ' => '501',
       'CA' => '1',
       'CC' => '61',
       'CD' => '243',
       'CF' => '236',
       'CG' => '242',
       'CH' => '41',
       'CI' => '225',
       'CK' => '682',
       'CL' => '56',
       'CM' => '237',
       'CN' => '86',
       'CO' => '57',
       'CR' => '506',
       'CU' => '53',
       'CV' => '238',
       'CW' => '599',
       'CX' => '61',
       'CY' => '357',
       'CZ' => '420',
       'DE' => '49',
       'DJ' => '253',
       'DK' => '45',
       'DM' => '1-767',
       'DO' => '1-809',
       'DZ' => '213',
       'EC' => '593',
       'EE' => '372',
       'EG' => '20',
       'EH' => '212',
       'ER' => '291',
       'ES' => '34',
       'ET' => '251',
       'FI' => '358',
       'FJ' => '679',
       'FK' => '500',
       'FO' => '298',
       'FR' => '33',
       'GA' => '241',
       'GB' => '44',
       'GD' => '1-473',
       'GE' => '995',
       'GF' => '594',
       'GG' => '44',
       'GH' => '233',
       'GI' => '350',
       'GL' => '299',
       'GM' => '220',
       'GN' => '224',
       'GP' => '590',
       'GQ' => '240',
       'GR' => '30',
       'GS' => '500',
       'GT' => '502',
       'GW' => '245',
       'GY' => '592',
       'HM' => '672',
       'HN' => '504',
       'HR' => '385',
       'HT' => '509',
       'HU' => '36',
       'ID' => '62',
       'IE' => '353',
       'IL' => '972',
       'IM' => '44',
       'IN' => '91',
       'IO' => '246',
       'IQ' => '964',
       'IR' => '98',
       'IS' => '354',
       'IT' => '39',
       'JE' => '44',
       'JM' => '1-876',
       'JO' => '962',
       'JP' => '81',
       'KE' => '254',
       'KG' => '996',
       'KH' => '855',
       'KI' => '686',
       'KM' => '269',
       'KN' => '1-869',
       'KP' => '850',
       'KR' => '82',
       'KW' => '965',
       'KY' => '1-345',
       'KZ' => '7',
       'LA' => '856',
       'LB' => '961',
       'LC' => '1-758',
       'LI' => '423',
       'LK' => '94',
       'LR' => '231',
       'LS' => '266',
       'LT' => '370',
       'LU' => '352',
       'LV' => '371',
       'LY' => '218',
       'MA' => '212',
       'MC' => '377',
       'MD' => '373',
       'ME' => '382',
       'MF' => '590',
       'MG' => '261',
       'MK' => '389',
       'ML' => '223',
       'MM' => '95',
       'MN' => '976',
       'MO' => '853',
       'MQ' => '596',
       'MR' => '222',
       'MS' => '1-664',
       'MT' => '356',
       'MU' => '230',
       'MV' => '960',
       'MW' => '265',
       'MX' => '52',
       'MY' => '60',
       'MZ' => '258',
       'NA' => '264',
       'NC' => '687',
       'NE' => '227',
       'NF' => '672',
       'NG' => '234',
       'NI' => '505',
       'NL' => '31',
       'NO' => '47',
       'NP' => '977',
       'NR' => '674',
       'NU' => '683',
       'NZ' => '64',
       'OM' => '968',
       'PA' => '507',
       'PE' => '51',
       'PF' => '689',
       'PG' => '675',
       'PH' => '63',
       'PK' => '92',
       'PL' => '48',
       'PM' => '508',
       'PN' => '870',
       'PS' => '970',
       'PT' => '351',
       'PY' => '595',
       'QA' => '974',
       'RE' => '262',
       'RO' => '40',
       'RS' => '381',
       'RU' => '7',
       'RW' => '250',
       'SA' => '966',
       'SB' => '677',
       'SC' => '248',
       'SD' => '249',
       'SE' => '46',
       'SG' => '65',
       'SH' => '290',
       'SI' => '386',
       'SJ' => '47',
       'SK' => '421',
       'SL' => '232',
       'SM' => '378',
       'SN' => '221',
       'SO' => '252',
       'SR' => '597',
       'SS' => '211',
       'ST' => '239',
       'SV' => '503',
       'SX' => '1-721',
       'SY' => '963',
       'SZ' => '268',
       'TC' => '1-649',
       'TD' => '235',
       'TF' => '262',
       'TG' => '228',
       'TH' => '66',
       'TJ' => '992',
       'TK' => '690',
       'TL' => '670',
       'TM' => '993',
       'TN' => '216',
       'TO' => '676',
       'TR' => '90',
       'TT' => '1-868',
       'TV' => '688',
       'TW' => '886',
       'TZ' => '255',
       'UA' => '380',
       'UG' => '256',
       'US' => '1',
       'UY' => '598',
       'UZ' => '998',
       'VA' => '39-06',
       'VC' => '1-784',
       'VE' => '58',
       'VG' => '1-284',
       'VN' => '84',
       'VU' => '678',
       'WF' => '681',
       'WS' => '685',
       'XK' => '383',
       'YE' => '967',
       'YT' => '262',
       'ZA' => '27',
       'ZM' => '260',
       'ZW' => '263',
            'Andorra' => '376',
       'United Arab Emirates' => '971',
       'Afghanistan' => '93',
       'Antigua and Barbuda' => '1-268',
       'Anguilla' => '1-264',
       'Albania' => '355',
       'Armenia' => '374',
       'Angola' => '244',
       'Antarctica' => 'N/A',
       'Argentina' => '54',
       'Austria' => '43',
       'Australia' => '61',
       'Aruba' => '297',
       'Åland Islands' => '358-18',
       'Azerbaijan' => '994',
       'Bosnia and Herzegovina' => '387',
       'Barbados' => '1-246',
       'Bangladesh' => '880',
       'Belgium' => '32',
       'Burkina Faso' => '226',
       'Bulgaria' => '359',
       'Bahrain' => '973',
       'Burundi' => '257',
       'Benin' => '229',
       'Saint Barthélemy' => '590',
       'Bermuda' => '1-441',
       'Brunei Darussalam' => '673',
       'Bolivia, Plurinational State of' => '591',
       'Bonaire, Sint Eustatius and Saba' => '599',
          'Brazil' => '55',
       'Bahamas' => '1-242',
       'Bhutan' => '975',
       'Bouvet Island' => 'N/A',
       'Botswana' => '267',
       'Belarus' => '375',
       'Belize' => '501',
       'Canada' => '1',
       'Cocos (Keeling) Islands' => '61',
       'Congo, The Democratic Republic of the' => '243',
       'Central African Republic' => '236',
       'Congo' => '242',
       'Switzerland' => '41',
           'Cote d\'Ivoire' => '225',
          'Cook Islands' => '682',
       'Chile' => '56',
       'Cameroon' => '237',
       'China' => '86',
       'Colombia' => '57',
       'Costa Rica' => '506',
       'Cuba' => '53',
       'Cabo Verde' => '238',
       'Curaçao' => '599',
       'Christmas Island' => '61',
       'Cyprus' => '357',
       'Czech Republic' => '420',
       'Germany' => '49',
       'Djibouti' => '253',
       'Denmark' => '45',
       'Dominica' => '1-767',
       'Dominican Republic' => '1-809',
          'Algeria' => '213',
       'Ecuador' => '593',
       'Estonia' => '372',
       'Egypt' => '20',
       'Western Sahara' => '212',
       'Eritrea' => '291',
       'Spain' => '34',
       'Ethiopia' => '251',
       'Finland' => '358',
       'Fiji' => '679',
       'Falkland Islands (Malvinas)' => '500',
       'Faroe Islands' => '298',
       'France' => '33',
       'Gabon' => '241',
       'United Kingdom' => '44',
       'Grenada' => '1-473',
       'Georgia' => '995',
       'French Guiana' => '594',
       'Guernsey' => '44',
       'Ghana' => '233',
       'Gibraltar' => '350',
       'Greenland' => '299',
       'Gambia' => '220',
       'Guinea' => '224',
       'Guadeloupe' => '590',
       'Equatorial Guinea' => '240',
       'Greece' => '30',
       'South Georgia and the South Sandwich Islands' => '500',
       'Guatemala' => '502',
       'Guinea-Bissau' => '245',
       'Guyana' => '592',
           'Heard Island and McDonald Islands' => 'N/A',
       'Honduras' => '504',
       'Croatia' => '385',
       'Haiti' => '509',
       'Hungary' => '36',
       'Indonesia' => '62',
       'Ireland' => '353',
       'Israel' => '972',
       'Isle of Man' => '44',
       'India' => '91',
       'British Indian Ocean Territory' => '246',
       'Iraq' => '964',
       'Iran, Islamic Republic of' => '98',
       'Iceland' => '354',
       'Italy' => '39',
       'Jersey' => '44',
       'Jamaica' => '1-876',
       'Jordan' => '962',
       'Japan' => '81',
       'Kenya' => '254',
       'Kyrgyzstan' => '996',
       'Cambodia' => '855',
       'Kiribati' => '686',
       'Comoros' => '269',
       'Saint Kitts and Nevis' => '1-869',
       'Korea, Democratic People\'s Republic of' => '850',
       'Korea, Republic of' => '82',
       'Kuwait' => '965',
       'Cayman Islands' => '1-345',
       'Kazakhstan' => '7',
       'Lao People\'s Democratic Republic' => '856',
        'Lebanon' => '961',
       'Saint Lucia' => '1-758',
       'Liechtenstein' => '423',
       'Sri Lanka' => '94',
       'Liberia' => '231',
       'Lesotho' => '266',
       'Lithuania' => '370',
       'Luxembourg' => '352',
       'Latvia' => '371',
       'Libya' => '218',
       'Morocco' => '212',
       'Monaco' => '377',
       'Moldova, Republic of' => '373',
       'Montenegro' => '382',
       'Saint Martin (French part)' => '590',
       'Madagascar' => '261',
       'North Macedonia' => '389',
       'Mali' => '223',
       'Myanmar' => '95',
       'Mongolia' => '976',
       'Macao' => '853',
       'Martinique' => '596',
       'Mauritania' => '222',
       'Montserrat' => '1-664',
       'Malta' => '356',
       'Mauritius' => '230',
       'Maldives' => '960',
       'Malawi' => '265',
       'Mexico' => '52',
       'Malaysia' => '60',
       'Mozambique' => '258',
       'Namibia' => '264',
       'New Caledonia' => '687',
       'Niger' => '227',
       'Norfolk Island' => '672',
       'Nigeria' => '234',
       'Nicaragua' => '505',
       'Netherlands' => '31',
       'Norway' => '47',
       'Nepal' => '977',
       'Nauru' => '674',
       'Niue' => '683',
       'New Zealand' => '64',
       'Oman' => '968',
       'Panama' => '507',
       'Peru' => '51',
       'French Polynesia' => '689',
       'Papua New Guinea' => '675',
       'Philippines' => '63',
       'Pakistan' => '92',
       'Poland' => '48',
       'Saint Pierre and Miquelon' => '508',
       'Pitcairn' => '64',
       'Palestine, State of' => '970',
       'Portugal' => '351',
       'Paraguay' => '595',
       'Qatar' => '974',
       'Réunion' => '262',
       'Romania' => '40',
       'Serbia' => '381',
       'Russian Federation' => '7',
       'Rwanda' => '250',
       'Saudi Arabia' => '966',
       'Solomon Islands' => '677',
       'Seychelles' => '248',
       'Sudan' => '249',
       'Sweden' => '46',
       'Singapore' => '65',
       'Saint Helena, Ascension and Tristan da Cunha' => '290',
       'Slovenia' => '386',
       'Svalbard and Jan Mayen' => '47',
       'Slovakia' => '421',
       'Sierra Leone' => '232',
       'San Marino' => '378',
       'Senegal' => '221',
       'Somalia' => '252',
       'Suriname' => '597',
       'South Sudan' => '211',
       'Sao Tome and Principe' => '239',
       'El Salvador' => '503',
       'Sint Maarten (Dutch part)' => '1-721',
       'Syrian Arab Republic' => '963',
       'Eswatini' => '268',
       'Turks and Caicos Islands' => '1-649',
       'Chad' => '235',
       'French Southern Territories' => '262',
       'Togo' => '228',
       'Thailand' => '66',
       'Tajikistan' => '992',
       'Tokelau' => '690',
       'Timor-Leste' => '670',
       'Turkmenistan' => '993',
       'Tunisia' => '216',
       'Tonga' => '676',
       'Turkey' => '90',
       'Trinidad and Tobago' => '1-868',
       'Tuvalu' => '688',
       'Taiwan, Province of China' => '886',
       'Tanzania, United Republic of' => '255',
       'Ukraine' => '380',
       'Uganda' => '256',
       'United States' => '1',
       'Uruguay' => '598',
       'Uzbekistan' => '998',
       'Holy See (Vatican City State)' => '379',
       'Saint Vincent and the Grenadines' => '1-784',
       'Venezuela, Bolivarian Republic of' => '58',
       'Virgin Islands, British' => '1-284',
       'Viet Nam' => '84',
       'Vanuatu' => '678',
       'Wallis and Futuna' => '681',
       'Samoa' => '685',
       'Yemen' => '967',
       'Mayotte' => '262',
       'South Africa' => '27',
       'Zambia' => '260',
       'Zimbabwe' => '263'
    };

    /**
     * @description
     * @param newLeads List of Leads
     * @param context String context
     * Method Name     : updatePhoneWithCountryCode
     * Created By      : Preksha Chauhan
     * Created Date    : 07/18/2024
     * Description     : This method updates the phone numbers of leads in the provided 
     *                   list by appending the appropriate country code, if not already 
     *                   present. It checks each lead's phone number and ensures it starts 
     *                   with the correct country code based on the lead's country.
    *******************************************************************************************/
    public static void updatePhoneWithCountryCode(List<Lead> newLeads, String context) {
        for (Lead lead : newLeads) {
            if (lead.Phone != null) {
                String phoneNumber = lead.Phone.trim();
                String countryCode = getCountryCodeForLead(lead);
                
                // Check if the number already starts with the country code
                if (!phoneNumber.startsWith(countryCode)) {
                    lead.Phone = countryCode + phoneNumber;
                }
                // If it starts with the country code, do nothing
            }
        }
    }

   /**
    * @description
    * @param lead  Leads
     * Method Name     : getCountryCodeForLead
     * Created By      : Preksha Chauhan
     * Created Date    : 07/18/2024
     * Description     : This method determines the country code for a lead based on its 
     *                   country. If the lead's country is found in the country code map, 
     *                   it returns the corresponding code; otherwise, it defaults to 
     *                   India ('91').
    *******************************************************************************************/
    public static String getCountryCodeForLead(Lead lead) {
        // Assume the Country field is available in the Lead object
        // Replace 'Country' with your actual field API name if different
        String country = lead.Country;

        // If the country is in the map, return the corresponding code, else default to India ('91')
        return countryCodeMap.containsKey(country) ? countryCodeMap.get(country) : '91';
    }
    
    /**
    * @description
    * @param countryName  Name of Country
    * @param phoneNumber  Phone number
    * @return updated Phone number
     * Method Name     : generatePhoneNumberWithCountryCode
     * Created By      : Preksha Chauhan
     * Created Date    : 07/18/2024
     * Description     : This method generates a phone number by combining the country code 
     *                   with the provided phone number. It cleans the phone number by 
     *                   removing any non-digit characters before appending the country code.
    *******************************************************************************************/
    public static String generatePhoneNumberWithCountryCode(String countryName, String phoneNumber) {
        String newCountryCode = countryCodeMap.get(countryName);
        //System.debug('Country Code: ' + newCountryCode + ' Phone Number: ' + phoneNumber);
        String updatePhoneNumber = newCountryCode + phoneNumber.replaceAll('\\D', ''); // Ensure only digits are appended
       //system.debug('565 ------ updatePhoneNumber' +updatePhoneNumber);
        return updatePhoneNumber;
    }

    /**
    * @description
    * @param leads  List of leads
     * Method Name     : handleDuplicateLeads
     * Created By      : Preksha Chauhan
     * Created Date    : 10/09/2024
     * Description     : This method checks for existing leads with the same email and phone
     *                   number for the Masters record type. If a duplicate is found, it 
     *                   updates the existing lead's multi lead source and lead source fields.
    *******************************************************************************************/
    public static void handleDuplicateLeads(List<Lead> leads) {
        //Set<String> emailPhoneSet = new Set<String>();
        Map<String, Lead> existingLeads = new Map<String, Lead>();
        Set<String> emailSet = new Set<String>();
        Set<String> phoneSet = new Set<String>();
        Set<Id> recordTypeIds = new Set<Id>();
    
        // Collect email and phone combinations from new leads
        for (Lead lead : leads) {
            if (lead.Email != null) {
                emailSet.add(lead.Email);
            }
            if (lead.Phone != null) {
                phoneSet.add(lead.Phone);
            }
        }
    
        // Get Record Type Ids for 'Masters' from custom metadata
        List<Department_Record_Type_Mapping__mdt> recordTypeMappings = [
            SELECT Record_Type_Id__c 
            FROM Department_Record_Type_Mapping__mdt 
            WHERE Department__c = 'Masters'
        ];
    
        for (Department_Record_Type_Mapping__mdt mapping : recordTypeMappings) {
            recordTypeIds.add(mapping.Record_Type_Id__c);
        }
    
        // Query existing leads with the same email or phone number and correct record type
        if (!emailSet.isEmpty() || !phoneSet.isEmpty()) {
            existingLeads = new Map<String, Lead>(
                [SELECT Id, Email, Phone, LeadSource, Multi_Select_Lead_Source__c 
                 FROM Lead 
                 WHERE (Email IN :emailSet OR Phone IN :phoneSet) 
                 AND RecordTypeId IN :recordTypeIds]
            );
        }
    
        // Handle duplicates found
        for (Lead lead : leads) {
            String key = lead.Email + ':' + lead.Phone;
            
            // Check for duplicates using both email and phone
            for (Lead existingLead : existingLeads.values()) {
                String existingKey = existingLead.Email + ':' + existingLead.Phone;
                if (key == existingKey) {
                    // Update Multi_Select_Lead_Source__c
                    if (existingLead.Multi_Select_Lead_Source__c != null) {
                        existingLead.Multi_Select_Lead_Source__c += ';' + lead.LeadSource;
                    } else {
                        existingLead.Multi_Select_Lead_Source__c = lead.LeadSource;
                    }
    
                    // Update LeadSource to the latest one
                    existingLead.LeadSource = lead.LeadSource;
    
                    // To avoid creating a new lead, mark the new lead with an error
                    lead.addError('Duplicate lead found. Existing lead updated instead.');
    
                    // Optionally, add existingLead to a list for updating later
                    existingLeads.put(existingLead.Id, existingLead);
                    break;
                }
            }
        }
    
        // Perform updates for existing leads
        if (!existingLeads.isEmpty()) {
            update existingLeads.values();
        }
    }  

    /******************************************************************************************
    * Method Name       : initializeLeadFields
    * Created By        : Preksha Chauhan
    * Created Date      : 08/09/2024
    * Description       : This method handles Lead records before they are inserted. It
    *                     checks if the LastName is blank and, if so, sets it to the value of
    *                     FirstName. This ensures that the LastName field is always populated
    *                     with the FirstName value if it was not provided.
    * Parameters        : List<Lead> newLeads - The list of Lead records that are being inserted.
    * Return Type       : void
    ******************************************************************************************/

    /**
    * @description initialize Lead Fields
    * @param newLeads  List of leads
    */
    public static void initializeLeadFields(List<Lead> newLeads) {
        for (Lead lead : newLeads) {
            // Check if LastName is blank
            if (String.isBlank(lead.LastName)) {
                // Set LastName to '.' if it is blank
                lead.LastName = '.';
            }
            // Ensure FirstName is retained
            lead.FirstName = lead.FirstName;
            lead.Salutation__c = lead.Salutation;
        }
    }
        
    /******************************************************************************************
    * Method Name       : updateLeadLastNameIfBlank
    * Created By        : Preksha Chauhan
    * Created Date      : 08/09/2024
    * Description       : This method handles Lead records before they are updated. It
    *                     checks if the LastName is blank and was previously set (not blank),
    *                     then updates LastName to the value of FirstName. This ensures that
    *                     the LastName field is populated with the FirstName value if it was
    *                     not provided during the update.
    * Parameters        : List<Lead> newLeads - The list of Lead records that are being updated.
    *                     Map<Id, Lead> oldLeadsMap - A map of Lead records before the update.
    * Return Type       : void
    ******************************************************************************************/
    /**
    * @description update lastname of lead if blank
    * @param newLeads  List of leads
    * @param oldLeadsMap  Map of old leads
    */
    public static void updateLeadLastNameIfBlank(List<Lead> newLeads, Map<Id, Lead> oldLeadsMap) {
        for (Lead lead : newLeads) {
            Lead oldLead = oldLeadsMap.get(lead.Id);
            
            // Check if LastName is blank and was not blank before update
            if (String.isBlank(lead.LastName) && !String.isBlank(oldLead.LastName)) {
                // Set LastName to '.' if it is blank
                lead.LastName = '.';
                // Optionally set FirstName to null if LastName was blank
                lead.FirstName = null;
            }
        }
    }
}