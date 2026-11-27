/**
 * @description Tests WaTemplateValidator against Meta's template rules: valid Marketing, Utility and
 *              Authentication payloads, and one negative case per rule (name, language, category, header,
 *              body variables, footer, button counts and grouping, URL/phone/copy-code, OTP buttons).
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
private class WaTemplateValidatorTest {
    private static Map<String, Object> template(String category, String componentsJson) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            '{"name":"test_template","language":"en_US","category":"' + category + '","components":[' + componentsJson + ']}'
        );
    }

    private static final String BODY_OK = '{"type":"BODY","text":"Hello, your application is received."}';

    private static String buttons(String buttonsJson) {
        return BODY_OK + ',{"type":"BUTTONS","buttons":[' + buttonsJson + ']}';
    }

    private static void assertRejected(Map<String, Object> input, String expectedText) {
        try {
            WaTemplateValidator.validateAndBuild(input);
            Assert.fail('Expected rejection containing: ' + expectedText);
        } catch (WaException caught) {
            Assert.areEqual(400, caught.statusCode, 'Validation errors are 400');
            Assert.isTrue(caught.getMessage().contains(expectedText), 'Expected "' + expectedText + '" in: ' + caught.getMessage());
        }
    }

    @IsTest
    static void validMarketingTemplateIsRebuiltWithKnownKeysOnly() {
        Map<String, Object> input = (Map<String, Object>) JSON.deserializeUntyped(WaTestSupport.marketingTemplateJson());
        input.put('unexpected_key', 'dropped');

        Map<String, Object> payload = WaTemplateValidator.validateAndBuild(input);

        Assert.isFalse(payload.containsKey('unexpected_key'), 'Unknown keys are never sent to Meta');
        List<Object> components = (List<Object>) payload.get('components');
        Assert.areEqual(4, components.size(), 'Header, body, footer and buttons');
        Map<String, Object> body = (Map<String, Object>) components[1];
        Assert.areEqual('BODY', body.get('type'), 'Components are in Meta order');
        String serialized = JSON.serialize(payload);
        Assert.isTrue(serialized.contains('"body_text":[["Asha","B.Tech"]]'), 'Body samples are nested as Meta expects: ' + serialized);
        Assert.isTrue(serialized.contains('"header_text":["Asha"]'), 'Header sample is sent');
        Assert.isTrue(serialized.contains('"example":["https://ahduni.edu.in/apply/btech"]'), 'URL example is sent');
        Assert.isTrue(serialized.contains('"example":"AU2027"'), 'Copy code example is a string');
    }

    @IsTest
    static void validUtilityTemplatesWithMediaAndLocationHeaders() {
        for (String format : new List<String>{ 'IMAGE', 'VIDEO', 'DOCUMENT' }) {
            Map<String, Object> payload = WaTemplateValidator.validateAndBuild(template('UTILITY',
                '{"type":"HEADER","format":"' + format + '","example":{"header_handle":["4::abc"]}},' + BODY_OK));
            Assert.isTrue(JSON.serialize(payload).contains('"header_handle":["4::abc"]'), format + ' header keeps the handle');
        }
        Map<String, Object> location = WaTemplateValidator.validateAndBuild(template('utility', '{"type":"HEADER","format":"LOCATION"},' + BODY_OK));
        Assert.areEqual('UTILITY', location.get('category'), 'Category is normalised to upper case');
    }

    @IsTest
    static void validAuthenticationTemplates() {
        Map<String, Object> copyCode = WaTemplateValidator.validateAndBuild(template('AUTHENTICATION',
            '{"type":"BODY","add_security_recommendation":true},{"type":"FOOTER","code_expiration_minutes":10},'
            + '{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"COPY_CODE","text":"Copy code"}]}'));
        String copySerialized = JSON.serialize(copyCode);
        Assert.isTrue(copySerialized.contains('"add_security_recommendation":true'), 'Security recommendation is kept');
        Assert.isTrue(copySerialized.contains('"code_expiration_minutes":10'), 'Expiry is kept');

        Map<String, Object> oneTap = WaTemplateValidator.validateAndBuild(template('AUTHENTICATION',
            '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"ONE_TAP","text":"Copy code","autofill_text":"Autofill",'
            + '"supported_apps":[{"package_name":"com.ahduni.app","signature_hash":"K8a/AINcGX7"}]}]}'));
        Assert.isTrue(JSON.serialize(oneTap).contains('"supported_apps":[{'), 'One-tap uses supported_apps');
    }

    @IsTest
    static void basicsAreValidated() {
        Map<String, Object> badName = template('UTILITY', BODY_OK);
        badName.put('name', 'Admission Open');
        assertRejected(badName, 'lowercase letters, numbers and underscores');

        Map<String, Object> longName = template('UTILITY', BODY_OK);
        longName.put('name', 'a'.repeat(513));
        assertRejected(longName, 'at most 512');

        Map<String, Object> noName = template('UTILITY', BODY_OK);
        noName.remove('name');
        assertRejected(noName, 'Enter a template name');

        Map<String, Object> badLanguage = template('UTILITY', BODY_OK);
        badLanguage.put('language', 'xx_YY');
        assertRejected(badLanguage, 'language supported by WhatsApp');

        assertRejected(template('PROMOTION', BODY_OK), 'Choose a category');
        assertRejected(template('UTILITY', ''), 'Enter the message body');
        assertRejected(template('UTILITY', BODY_OK + ',' + BODY_OK), 'Only one body');
        assertRejected(template('UTILITY', BODY_OK + ',{"type":"CAROUSEL"}'), 'Unknown template component');
        assertRejected(template('UTILITY', BODY_OK + ',"text"'), 'component is not valid');

        Map<String, Object> noComponents = template('UTILITY', BODY_OK);
        noComponents.put('components', 'none');
        assertRejected(noComponents, 'has no content');
        assertRejected(null, 'Enter a template name');
    }

    @IsTest
    static void bodyVariablesFollowMetaRules() {
        assertRejected(template('UTILITY', '{"type":"BODY","text":"' + 'a'.repeat(1025) + '"}'), 'at most 1024');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Hi {{1}} and {{3}} ok","example":{"body_text":[["a","b"]]}}'), 'no gaps');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"{{1}} is ready","example":{"body_text":[["a"]]}}'), 'can\'t start or end');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Your code is {{1}}","example":{"body_text":[["a"]]}}'), 'can\'t start or end');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Hi {{1}}, see {{2}} now"}'), 'sample value for every body variable');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Hi {{1}}, see {{2}} now","example":{"body_text":[["a",""]]}}'), 'sample value for every body variable');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Hi {{name}} there"}'), 'numbers in double braces');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"Hi {{1} there"}'), 'unmatched braces');
        assertRejected(template('UTILITY', '{"type":"BODY","text":"  "}'), 'Enter the message body');

        Map<String, Object> repeated = WaTemplateValidator.validateAndBuild(template('UTILITY',
            '{"type":"BODY","text":"Hi {{1}}, yes {{1}} again.","example":{"body_text":[["Asha"]]}}'));
        Assert.isNotNull(repeated, 'Reusing the same variable is allowed');
    }

    @IsTest
    static void headerRules() {
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"' + 'a'.repeat(61) + '"},' + BODY_OK), 'at most 60');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"*Big* news"},' + BODY_OK), 'formatting characters');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"Line\\nbreak"},' + BODY_OK), 'single line');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"Hi {{1}} {{2}}","example":{"header_text":["a"]}},' + BODY_OK), 'only one variable');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"Hi {{2}}","example":{"header_text":["a"]}},' + BODY_OK), 'only one variable');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":"Hi {{1}}"},' + BODY_OK), 'sample value for {{1}} in the header');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"TEXT","text":""},' + BODY_OK), 'Enter the header text');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"IMAGE"},' + BODY_OK), 'Upload a sample image');
        assertRejected(template('MARKETING', '{"type":"HEADER","format":"GIF"},' + BODY_OK), 'Choose a header type');
    }

    @IsTest
    static void footerRules() {
        assertRejected(template('UTILITY', BODY_OK + ',{"type":"FOOTER","text":"' + 'a'.repeat(61) + '"}'), 'at most 60');
        assertRejected(template('UTILITY', BODY_OK + ',{"type":"FOOTER","text":"Hi {{1}}"}'), 'can\'t contain variables');
        assertRejected(template('UTILITY', BODY_OK + ',{"type":"FOOTER","text":"a\\nb"}'), 'single line');
        assertRejected(template('UTILITY', BODY_OK + ',{"type":"FOOTER"}'), 'Enter the footer text');
    }

    @IsTest
    static void buttonCountsAndGrouping() {
        String quickReply = '{"type":"QUICK_REPLY","text":"Yes"}';
        String url = '{"type":"URL","text":"Visit","url":"https://ahduni.edu.in"}';
        String phone = '{"type":"PHONE_NUMBER","text":"Call","phone_number":"+917900000000"}';
        String code = '{"type":"COPY_CODE","example":"AU2027"}';

        assertRejected(template('MARKETING', buttons(String.join(new List<String>{ quickReply, quickReply, quickReply, quickReply, quickReply, quickReply, quickReply, quickReply, quickReply, quickReply, quickReply }, ','))), 'at most 10 buttons');
        assertRejected(template('MARKETING', buttons(url + ',' + url + ',' + url)), 'at most 2 website buttons');
        assertRejected(template('MARKETING', buttons(phone + ',' + phone)), 'only 1 call phone number');
        assertRejected(template('MARKETING', buttons(code + ',' + code)), 'only 1 copy offer code');
        assertRejected(template('MARKETING', buttons(quickReply + ',' + url + ',' + quickReply)), 'grouped together');
        assertRejected(template('UTILITY', buttons(code)), 'only available for Marketing');
        assertRejected(template('MARKETING', buttons('')), 'Add at least one button');
        assertRejected(template('MARKETING', buttons('{"type":"FLOW","text":"x"}')), 'choose a button type');

        Map<String, Object> grouped = WaTemplateValidator.validateAndBuild(template('MARKETING', buttons(url + ',' + phone + ',' + quickReply + ',' + quickReply)));
        Assert.isNotNull(grouped, 'Other buttons first, then quick replies, is valid');
    }

    @IsTest
    static void buttonFieldRules() {
        assertRejected(template('MARKETING', buttons('{"type":"QUICK_REPLY","text":"' + 'a'.repeat(26) + '"}')), 'up to 25 characters');
        assertRejected(template('MARKETING', buttons('{"type":"URL","text":"Go","url":"ahduni.edu.in"}')), 'starting with https://');
        assertRejected(template('MARKETING', buttons('{"type":"URL","text":"Go","url":"https://a.in/{{1}}/x"}')), 'at the very end');
        assertRejected(template('MARKETING', buttons('{"type":"URL","text":"Go","url":"https://a.in/{{2}}"}')), 'at the very end');
        assertRejected(template('MARKETING', buttons('{"type":"URL","text":"Go","url":"https://a.in/{{1}}"}')), 'sample full website address');
        assertRejected(template('MARKETING', buttons('{"type":"PHONE_NUMBER","text":"Call","phone_number":"call me"}')), 'country code');
        assertRejected(template('MARKETING', buttons('{"type":"COPY_CODE","example":"HAS SPACE"}')), 'sample offer code');
        assertRejected(template('MARKETING', buttons('{"type":"COPY_CODE","example":"' + 'A'.repeat(21) + '"}')), 'sample offer code');
    }

    @IsTest
    static void authenticationRules() {
        String copyButton = '{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"COPY_CODE"}]}';
        assertRejected(template('AUTHENTICATION', '{"type":"HEADER","format":"TEXT","text":"x"},{"type":"BODY"},' + copyButton), 'can\'t have a header');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY","text":"Your code"},' + copyButton), 'fixed code message');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"FOOTER","code_expiration_minutes":91},' + copyButton), 'from 1 to 90');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"FOOTER","code_expiration_minutes":2.5},' + copyButton), 'from 1 to 90');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"FOOTER","code_expiration_minutes":"ten"},' + copyButton), 'from 1 to 90');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"}'), 'exactly one button');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"ZERO_TAP"}]}'), 'Choose the code button');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"COPY_CODE","text":"' + 'a'.repeat(26) + '"}]}'), 'at most 25');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"ONE_TAP"}]}'), '1 to 5 Android apps');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"ONE_TAP","supported_apps":[{"package_name":"app","signature_hash":"short"}]}]}'), 'Android package name');
        assertRejected(template('AUTHENTICATION', '{"type":"BODY"},{"type":"BUTTONS","buttons":[{"type":"OTP","otp_type":"ONE_TAP","supported_apps":[{"package_name":"com.au.app","signature_hash":"short"}]}]}'), 'exactly 11 characters');
    }
}