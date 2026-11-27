/**
 * @description Domain rules for creating a WhatsApp message template, mirroring Meta's documented rules
 *              (WhatsApp Business Management API docs, read 2026-11-26). Validates the JSON sent by the page
 *              and builds a clean Meta payload that contains only known keys. All problems are collected and
 *              returned together as one 400 error so the user can fix them in one go.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
public with sharing class WaTemplateValidator {
    public static final String CATEGORY_MARKETING = 'MARKETING';
    public static final String CATEGORY_UTILITY = 'UTILITY';
    public static final String CATEGORY_AUTHENTICATION = 'AUTHENTICATION';
    public static final Set<String> CATEGORIES = new Set<String>{ CATEGORY_MARKETING, CATEGORY_UTILITY, CATEGORY_AUTHENTICATION };

    public static final String COMPONENT_HEADER = 'HEADER';
    public static final String COMPONENT_BODY = 'BODY';
    public static final String COMPONENT_FOOTER = 'FOOTER';
    public static final String COMPONENT_BUTTONS = 'BUTTONS';
    private static final List<String> COMPONENT_ORDER = new List<String>{ COMPONENT_HEADER, COMPONENT_BODY, COMPONENT_FOOTER, COMPONENT_BUTTONS };

    public static final String FORMAT_TEXT = 'TEXT';
    public static final String FORMAT_IMAGE = 'IMAGE';
    public static final String FORMAT_VIDEO = 'VIDEO';
    public static final String FORMAT_DOCUMENT = 'DOCUMENT';
    public static final String FORMAT_LOCATION = 'LOCATION';
    private static final Set<String> MEDIA_FORMATS = new Set<String>{ FORMAT_IMAGE, FORMAT_VIDEO, FORMAT_DOCUMENT };

    public static final String BUTTON_QUICK_REPLY = 'QUICK_REPLY';
    public static final String BUTTON_URL = 'URL';
    public static final String BUTTON_PHONE = 'PHONE_NUMBER';
    public static final String BUTTON_COPY_CODE = 'COPY_CODE';
    public static final String BUTTON_OTP = 'OTP';
    public static final String OTP_COPY_CODE = 'COPY_CODE';
    public static final String OTP_ONE_TAP = 'ONE_TAP';

    @TestVisible
    private static final Integer NAME_MAX = 512;
    @TestVisible
    private static final Integer HEADER_TEXT_MAX = 60;
    @TestVisible
    private static final Integer BODY_MAX = 1024;
    @TestVisible
    private static final Integer FOOTER_MAX = 60;
    @TestVisible
    private static final Integer BUTTON_TEXT_MAX = 25;
    private static final Integer URL_MAX = 2000;
    private static final Integer PHONE_MAX = 20;
    private static final Integer COPY_CODE_EXAMPLE_MAX = 20;
    private static final Integer MAX_BUTTONS = 10;
    private static final Integer MAX_QUICK_REPLY = 10;
    private static final Integer MAX_URL_BUTTONS = 2;
    private static final Integer MAX_PHONE_BUTTONS = 1;
    private static final Integer MAX_COPY_CODE_BUTTONS = 1;
    private static final Integer CODE_EXPIRY_MIN = 1;
    private static final Integer CODE_EXPIRY_MAX = 90;
    private static final Integer MAX_SUPPORTED_APPS = 5;
    private static final Integer PACKAGE_NAME_MAX = 224;
    private static final String URL_VARIABLE = '{{1}}';

    private static final Pattern NAME_PATTERN = Pattern.compile('^[a-z0-9_]+$');
    private static final Pattern TOKEN_PATTERN = Pattern.compile('\\{\\{([^{}]*)\\}\\}');
    private static final Pattern POSITIONAL_PATTERN = Pattern.compile('^[1-9][0-9]{0,2}$');
    private static final Pattern STARTS_WITH_VARIABLE = Pattern.compile('^\\{\\{[^{}]*\\}\\}[\\s\\S]*');
    private static final Pattern ENDS_WITH_VARIABLE = Pattern.compile('[\\s\\S]*\\{\\{[^{}]*\\}\\}$');
    private static final Pattern MARKDOWN_PATTERN = Pattern.compile('[*_~`]');
    private static final Pattern URL_PATTERN = Pattern.compile('^https?://[^\\s]+$');
    private static final Pattern PHONE_PATTERN = Pattern.compile('^\\+?[0-9]{6,19}$');
    private static final Pattern PACKAGE_PATTERN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$');
    private static final Pattern SIGNATURE_PATTERN = Pattern.compile('^[a-zA-Z0-9+/=]{11}$');

    /** Meta's supported template languages (118 codes, docs read 2026-11-26). */
    public static final Set<String> LANGUAGES = new Set<String>{
        'af', 'sq', 'ar', 'ar_EG', 'ar_AE', 'ar_LB', 'ar_MA', 'ar_QA', 'az', 'be_BY', 'bn', 'bn_IN', 'bg', 'ca',
        'zh_CN', 'zh_HK', 'zh_TW', 'hr', 'cs', 'da', 'prs_AF', 'nl', 'nl_BE', 'en', 'en_GB', 'en_US', 'en_AE',
        'en_AU', 'en_CA', 'en_GH', 'en_IE', 'en_IN', 'en_JM', 'en_MY', 'en_NZ', 'en_QA', 'en_SG', 'en_UG', 'en_ZA',
        'et', 'fil', 'fi', 'fr', 'fr_BE', 'fr_CA', 'fr_CH', 'fr_CI', 'fr_MA', 'ka', 'de', 'de_AT', 'de_CH', 'el',
        'gu', 'ha', 'he', 'hi', 'hu', 'id', 'ga', 'it', 'ja', 'kn', 'kk', 'rw_RW', 'ko', 'ky_KG', 'lo', 'lv', 'lt',
        'mk', 'ms', 'ml', 'mr', 'nb', 'ps_AF', 'fa', 'pl', 'pt_BR', 'pt_PT', 'pa', 'ro', 'ru', 'sr', 'si_LK', 'sk',
        'sl', 'es', 'es_AR', 'es_CL', 'es_CO', 'es_CR', 'es_DO', 'es_EC', 'es_HN', 'es_MX', 'es_PA', 'es_PE',
        'es_ES', 'es_UY', 'sw', 'sv', 'ta', 'te', 'th', 'tr', 'uk', 'ur', 'uz', 'vi', 'zu'
    };

    private final List<String> errors = new List<String>();

    /**
     * @description Validates a create request and returns the Meta payload.
     * @param input parsed JSON from the page
     * @return payload for POST /{waba}/message_templates
     */
    public static Map<String, Object> validateAndBuild(Map<String, Object> input) {
        WaTemplateValidator validator = new WaTemplateValidator();
        Map<String, Object> payload = validator.build(input == null ? new Map<String, Object>() : input);
        if (!validator.errors.isEmpty()) {
            throw WaException.of(400, String.join(validator.errors, '\n'));
        }
        return payload;
    }

    private Map<String, Object> build(Map<String, Object> input) {
        String name = asText(input.get('name'));
        String language = asText(input.get('language'));
        String category = asText(input.get('category'));
        category = category == null ? null : category.trim().toUpperCase();

        if (String.isBlank(name)) {
            errors.add('Enter a template name.');
        } else if (name.length() > NAME_MAX) {
            errors.add('The template name can be at most ' + NAME_MAX + ' characters.');
        } else if (!NAME_PATTERN.matcher(name).matches()) {
            errors.add('The template name can only contain lowercase letters, numbers and underscores.');
        }
        if (String.isBlank(language) || !LANGUAGES.contains(language)) {
            errors.add('Choose a language supported by WhatsApp.');
        }
        if (String.isBlank(category) || !CATEGORIES.contains(category)) {
            errors.add('Choose a category: Marketing, Utility or Authentication.');
        }

        Map<String, Map<String, Object>> byType = collectComponents(input.get('components'));
        List<Map<String, Object>> components = new List<Map<String, Object>>();
        if (category == CATEGORY_AUTHENTICATION) {
            components = buildAuthentication(byType);
        } else if (CATEGORIES.contains(category)) {
            components = buildStandard(category, byType);
        }

        return new Map<String, Object>{ 'name' => name, 'language' => language, 'category' => category, 'components' => components };
    }

    private Map<String, Map<String, Object>> collectComponents(Object rawComponents) {
        Map<String, Map<String, Object>> byType = new Map<String, Map<String, Object>>();
        if (!(rawComponents instanceof List<Object>)) {
            errors.add('The template has no content. Add a body.');
            return byType;
        }
        for (Object raw : (List<Object>) rawComponents) {
            if (!(raw instanceof Map<String, Object>)) {
                errors.add('A template component is not valid.');
                continue;
            }
            Map<String, Object> component = (Map<String, Object>) raw;
            String type = upper(component.get('type'));
            if (!COMPONENT_ORDER.contains(type)) {
                errors.add('Unknown template component "' + type + '".');
            } else if (byType.containsKey(type)) {
                errors.add('Only one ' + type.toLowerCase() + ' is allowed.');
            } else {
                byType.put(type, component);
            }
        }
        return byType;
    }

    private List<Map<String, Object>> buildStandard(String category, Map<String, Map<String, Object>> byType) {
        List<Map<String, Object>> components = new List<Map<String, Object>>();
        if (byType.containsKey(COMPONENT_HEADER)) {
            addIfNotNull(components, buildHeader(byType.get(COMPONENT_HEADER)));
        }
        if (byType.containsKey(COMPONENT_BODY)) {
            addIfNotNull(components, buildBody(byType.get(COMPONENT_BODY)));
        } else {
            errors.add('Enter the message body.');
        }
        if (byType.containsKey(COMPONENT_FOOTER)) {
            addIfNotNull(components, buildFooter(byType.get(COMPONENT_FOOTER)));
        }
        if (byType.containsKey(COMPONENT_BUTTONS)) {
            addIfNotNull(components, buildButtons(category, byType.get(COMPONENT_BUTTONS)));
        }
        return components;
    }

    private Map<String, Object> buildHeader(Map<String, Object> header) {
        String format = upper(header.get('format'));
        if (format == FORMAT_TEXT) {
            return buildTextHeader(header);
        }
        if (MEDIA_FORMATS.contains(format)) {
            String handle = firstText(asMap(header.get('example')).get('header_handle'));
            if (String.isBlank(handle)) {
                errors.add('Upload a sample ' + format.toLowerCase() + ' for the header.');
                return null;
            }
            return new Map<String, Object>{
                'type' => COMPONENT_HEADER,
                'format' => format,
                'example' => new Map<String, Object>{ 'header_handle' => new List<String>{ handle } }
            };
        }
        if (format == FORMAT_LOCATION) {
            return new Map<String, Object>{ 'type' => COMPONENT_HEADER, 'format' => FORMAT_LOCATION };
        }
        errors.add('Choose a header type: Text, Image, Video, Document or Location.');
        return null;
    }

    private Map<String, Object> buildTextHeader(Map<String, Object> header) {
        String text = asText(header.get('text'));
        if (String.isBlank(text)) {
            errors.add('Enter the header text, or choose no header.');
            return null;
        }
        if (text.length() > HEADER_TEXT_MAX) {
            errors.add('The header can be at most ' + HEADER_TEXT_MAX + ' characters.');
        }
        if (text.contains('\n') || text.contains('\r')) {
            errors.add('The header must be a single line.');
        }
        if (MARKDOWN_PATTERN.matcher(text).find()) {
            errors.add('The header can\'t contain formatting characters (* _ ~ `).');
        }
        List<Integer> variables = parseVariables(text, 'header');
        Map<String, Object> component = new Map<String, Object>{ 'type' => COMPONENT_HEADER, 'format' => FORMAT_TEXT, 'text' => text };
        if (variables.isEmpty()) {
            return component;
        }
        if (variables.size() > 1 || variables[0] != 1 || countTokens(text) > 1) {
            errors.add('The header can have only one variable, {{1}}.');
            return component;
        }
        String sample = firstText(asMap(header.get('example')).get('header_text'));
        if (String.isBlank(sample)) {
            errors.add('Enter a sample value for {{1}} in the header.');
        } else {
            component.put('example', new Map<String, Object>{ 'header_text' => new List<String>{ sample } });
        }
        return component;
    }

    private Map<String, Object> buildBody(Map<String, Object> body) {
        String text = asText(body.get('text'));
        if (String.isBlank(text)) {
            errors.add('Enter the message body.');
            return null;
        }
        if (text.length() > BODY_MAX) {
            errors.add('The body can be at most ' + BODY_MAX + ' characters (now ' + text.length() + ').');
        }
        List<Integer> variables = parseVariables(text, 'body');
        Map<String, Object> component = new Map<String, Object>{ 'type' => COMPONENT_BODY, 'text' => text };
        if (variables.isEmpty()) {
            return component;
        }
        for (Integer i = 0; i < variables.size(); i++) {
            if (variables[i] != i + 1) {
                errors.add('Body variables must be numbered in order with no gaps: {{1}}, {{2}}, {{3}} and so on.');
                break;
            }
        }
        String trimmed = text.trim();
        if (STARTS_WITH_VARIABLE.matcher(trimmed).matches() || ENDS_WITH_VARIABLE.matcher(trimmed).matches()) {
            errors.add('The body can\'t start or end with a variable. Add some text before and after it.');
        }
        List<String> samples = new List<String>();
        List<Object> exampleRows = asList(asMap(body.get('example')).get('body_text'));
        List<Object> firstRow = exampleRows.isEmpty() ? new List<Object>() : asList(exampleRows[0]);
        for (Object sample : firstRow) {
            samples.add(asText(sample));
        }
        Boolean samplesComplete = samples.size() == variables.size();
        for (String sample : samples) {
            samplesComplete = samplesComplete && String.isNotBlank(sample);
        }
        if (!samplesComplete) {
            errors.add('Enter a sample value for every body variable ({{1}} to {{' + variables.size() + '}}).');
        } else {
            component.put('example', new Map<String, Object>{ 'body_text' => new List<Object>{ samples } });
        }
        return component;
    }

    private Map<String, Object> buildFooter(Map<String, Object> footer) {
        String text = asText(footer.get('text'));
        if (String.isBlank(text)) {
            errors.add('Enter the footer text, or remove the footer.');
            return null;
        }
        if (text.length() > FOOTER_MAX) {
            errors.add('The footer can be at most ' + FOOTER_MAX + ' characters.');
        }
        if (text.contains('{{') || text.contains('}}')) {
            errors.add('The footer can\'t contain variables.');
        }
        if (text.contains('\n') || text.contains('\r')) {
            errors.add('The footer must be a single line.');
        }
        return new Map<String, Object>{ 'type' => COMPONENT_FOOTER, 'text' => text };
    }

    private Map<String, Object> buildButtons(String category, Map<String, Object> buttonsComponent) {
        List<Object> rawButtons = asList(buttonsComponent.get('buttons'));
        if (rawButtons.isEmpty()) {
            errors.add('Add at least one button, or remove the buttons section.');
            return null;
        }
        if (rawButtons.size() > MAX_BUTTONS) {
            errors.add('A template can have at most ' + MAX_BUTTONS + ' buttons.');
        }
        Map<String, Integer> counts = new Map<String, Integer>{ BUTTON_QUICK_REPLY => 0, BUTTON_URL => 0, BUTTON_PHONE => 0, BUTTON_COPY_CODE => 0 };
        List<Map<String, Object>> buttons = new List<Map<String, Object>>();
        Integer groupChanges = 0;
        Boolean previousWasQuickReply;
        for (Integer i = 0; i < rawButtons.size(); i++) {
            Map<String, Object> raw = asMap(rawButtons[i]);
            String type = upper(raw.get('type'));
            String label = 'Button ' + (i + 1);
            if (!counts.containsKey(type)) {
                errors.add(label + ': choose a button type.');
                continue;
            }
            counts.put(type, counts.get(type) + 1);
            Boolean isQuickReply = type == BUTTON_QUICK_REPLY;
            if (previousWasQuickReply != null && previousWasQuickReply != isQuickReply) {
                groupChanges++;
            }
            previousWasQuickReply = isQuickReply;
            addIfNotNull(buttons, buildButton(category, type, raw, label));
        }
        if (counts.get(BUTTON_QUICK_REPLY) > MAX_QUICK_REPLY) {
            errors.add('A template can have at most ' + MAX_QUICK_REPLY + ' quick reply buttons.');
        }
        if (counts.get(BUTTON_URL) > MAX_URL_BUTTONS) {
            errors.add('A template can have at most ' + MAX_URL_BUTTONS + ' website buttons.');
        }
        if (counts.get(BUTTON_PHONE) > MAX_PHONE_BUTTONS) {
            errors.add('A template can have only ' + MAX_PHONE_BUTTONS + ' call phone number button.');
        }
        if (counts.get(BUTTON_COPY_CODE) > MAX_COPY_CODE_BUTTONS) {
            errors.add('A template can have only ' + MAX_COPY_CODE_BUTTONS + ' copy offer code button.');
        }
        if (groupChanges > 1) {
            errors.add('Quick reply buttons must be grouped together, either all before or all after the other buttons.');
        }
        return new Map<String, Object>{ 'type' => COMPONENT_BUTTONS, 'buttons' => buttons };
    }

    private Map<String, Object> buildButton(String category, String type, Map<String, Object> raw, String label) {
        if (type == BUTTON_COPY_CODE) {
            if (category != CATEGORY_MARKETING) {
                errors.add(label + ': copy offer code buttons are only available for Marketing templates.');
            }
            String code = asText(raw.get('example'));
            if (String.isBlank(code) || code.length() > COPY_CODE_EXAMPLE_MAX || code.containsWhitespace()) {
                errors.add(label + ': enter a sample offer code of up to ' + COPY_CODE_EXAMPLE_MAX + ' characters with no spaces.');
            }
            return new Map<String, Object>{ 'type' => BUTTON_COPY_CODE, 'example' => code };
        }
        String text = asText(raw.get('text'));
        if (String.isBlank(text) || text.length() > BUTTON_TEXT_MAX || text.contains('\n')) {
            errors.add(label + ': enter button text of up to ' + BUTTON_TEXT_MAX + ' characters.');
        }
        Map<String, Object> button = new Map<String, Object>{ 'type' => type, 'text' => text };
        if (type == BUTTON_URL) {
            validateUrlButton(raw, button, label);
        } else if (type == BUTTON_PHONE) {
            String phone = asText(raw.get('phone_number'));
            if (String.isBlank(phone) || phone.length() > PHONE_MAX || !PHONE_PATTERN.matcher(phone).matches()) {
                errors.add(label + ': enter the phone number with country code, digits only (for example +919876543210), up to ' + PHONE_MAX + ' characters.');
            }
            button.put('phone_number', phone);
        }
        return button;
    }

    private void validateUrlButton(Map<String, Object> raw, Map<String, Object> button, String label) {
        String url = asText(raw.get('url'));
        if (String.isBlank(url) || url.length() > URL_MAX || !URL_PATTERN.matcher(url).matches()) {
            errors.add(label + ': enter a website address starting with https:// (up to ' + URL_MAX + ' characters).');
            button.put('url', url);
            return;
        }
        button.put('url', url);
        Integer tokens = countTokens(url);
        if (tokens == 0 && !url.contains('{{') && !url.contains('}}')) {
            return;
        }
        if (tokens != 1 || !url.endsWith(URL_VARIABLE) || url.indexOf('{{') != url.length() - URL_VARIABLE.length()) {
            errors.add(label + ': a dynamic website address can have one variable, {{1}}, at the very end.');
            return;
        }
        String example = firstText(raw.get('example'));
        if (String.isBlank(example) || example.contains('{{') || !URL_PATTERN.matcher(example).matches()) {
            errors.add(label + ': enter a sample full website address for the dynamic part.');
            return;
        }
        button.put('example', new List<String>{ example });
    }

    private List<Map<String, Object>> buildAuthentication(Map<String, Map<String, Object>> byType) {
        List<Map<String, Object>> components = new List<Map<String, Object>>();
        if (byType.containsKey(COMPONENT_HEADER)) {
            errors.add('Authentication templates can\'t have a header.');
        }
        Map<String, Object> body = byType.containsKey(COMPONENT_BODY) ? byType.get(COMPONENT_BODY) : new Map<String, Object>();
        if (String.isNotBlank(asText(body.get('text')))) {
            errors.add('Authentication templates use WhatsApp\'s fixed code message. Remove the custom body text.');
        }
        components.add(new Map<String, Object>{
            'type' => COMPONENT_BODY,
            'add_security_recommendation' => body.get('add_security_recommendation') == true
        });
        if (byType.containsKey(COMPONENT_FOOTER)) {
            Integer minutes = asInteger(byType.get(COMPONENT_FOOTER).get('code_expiration_minutes'));
            if (minutes == null || minutes < CODE_EXPIRY_MIN || minutes > CODE_EXPIRY_MAX) {
                errors.add('Code expiry must be a whole number of minutes from ' + CODE_EXPIRY_MIN + ' to ' + CODE_EXPIRY_MAX + '.');
            } else {
                components.add(new Map<String, Object>{ 'type' => COMPONENT_FOOTER, 'code_expiration_minutes' => minutes });
            }
        }
        List<Object> rawButtons = byType.containsKey(COMPONENT_BUTTONS) ? asList(byType.get(COMPONENT_BUTTONS).get('buttons')) : new List<Object>();
        if (rawButtons.size() != 1) {
            errors.add('Authentication templates need exactly one button: Copy code or One-tap autofill.');
            return components;
        }
        Map<String, Object> button = buildOtpButton(asMap(rawButtons[0]));
        if (button != null) {
            components.add(new Map<String, Object>{ 'type' => COMPONENT_BUTTONS, 'buttons' => new List<Object>{ button } });
        }
        return components;
    }

    private Map<String, Object> buildOtpButton(Map<String, Object> raw) {
        String otpType = upper(raw.get('otp_type'));
        if (upper(raw.get('type')) != BUTTON_OTP || (otpType != OTP_COPY_CODE && otpType != OTP_ONE_TAP)) {
            errors.add('Choose the code button: Copy code or One-tap autofill.');
            return null;
        }
        Map<String, Object> button = new Map<String, Object>{ 'type' => BUTTON_OTP, 'otp_type' => otpType };
        putOptionalButtonText(button, raw, 'text', 'Copy code button text');
        if (otpType == OTP_COPY_CODE) {
            return button;
        }
        putOptionalButtonText(button, raw, 'autofill_text', 'Autofill button text');
        List<Object> rawApps = asList(raw.get('supported_apps'));
        if (rawApps.isEmpty() || rawApps.size() > MAX_SUPPORTED_APPS) {
            errors.add('One-tap autofill needs 1 to ' + MAX_SUPPORTED_APPS + ' Android apps (package name and signature hash).');
            return button;
        }
        List<Object> apps = new List<Object>();
        for (Object rawApp : rawApps) {
            Map<String, Object> app = asMap(rawApp);
            String packageName = asText(app.get('package_name'));
            String signatureHash = asText(app.get('signature_hash'));
            if (String.isBlank(packageName) || packageName.length() > PACKAGE_NAME_MAX || !PACKAGE_PATTERN.matcher(packageName).matches()) {
                errors.add('Enter a valid Android package name, for example com.example.app (up to ' + PACKAGE_NAME_MAX + ' characters).');
            }
            if (String.isBlank(signatureHash) || !SIGNATURE_PATTERN.matcher(signatureHash).matches()) {
                errors.add('The app signature hash must be exactly 11 characters (letters, numbers, + / =).');
            }
            apps.add(new Map<String, Object>{ 'package_name' => packageName, 'signature_hash' => signatureHash });
        }
        button.put('supported_apps', apps);
        return button;
    }

    private void putOptionalButtonText(Map<String, Object> button, Map<String, Object> raw, String key, String label) {
        String value = asText(raw.get(key));
        if (String.isBlank(value)) {
            return;
        }
        if (value.length() > BUTTON_TEXT_MAX) {
            errors.add(label + ' can be at most ' + BUTTON_TEXT_MAX + ' characters.');
        }
        button.put(key, value);
    }

    /**
     * @description Returns the distinct variable numbers used in the text, sorted. Adds errors for
     *              non-positional variables and unmatched braces.
     */
    private List<Integer> parseVariables(String text, String section) {
        Set<Integer> numbers = new Set<Integer>();
        Matcher tokens = TOKEN_PATTERN.matcher(text);
        while (tokens.find()) {
            String content = tokens.group(1);
            if (POSITIONAL_PATTERN.matcher(content).matches()) {
                numbers.add(Integer.valueOf(content));
            } else {
                errors.add('Variables in the ' + section + ' must be numbers in double braces, like {{1}}. Found {{' + content + '}}.');
            }
        }
        String leftover = TOKEN_PATTERN.matcher(text).replaceAll('');
        if (leftover.contains('{{') || leftover.contains('}}')) {
            errors.add('The ' + section + ' has unmatched braces. Variables look like {{1}}.');
        }
        List<Integer> sorted = new List<Integer>(numbers);
        sorted.sort();
        return sorted;
    }

    private static Integer countTokens(String text) {
        Integer count = 0;
        Matcher tokens = TOKEN_PATTERN.matcher(text);
        while (tokens.find()) {
            count++;
        }
        return count;
    }

    private static void addIfNotNull(List<Map<String, Object>> target, Map<String, Object> item) {
        if (item != null) {
            target.add(item);
        }
    }

    private static String asText(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof String ? (String) value : String.valueOf(value);
    }

    private static String upper(Object value) {
        String text = asText(value);
        return text == null ? null : text.trim().toUpperCase();
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String firstText(Object value) {
        List<Object> items = asList(value);
        return items.isEmpty() ? null : asText(items[0]);
    }

    private static Integer asInteger(Object value) {
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            Long longValue = (Long) value;
            return longValue > 100000 ? null : longValue.intValue();
        }
        if (value instanceof Decimal) {
            Decimal decimalValue = (Decimal) value;
            return decimalValue.scale() > 0 && decimalValue != decimalValue.round(System.RoundingMode.DOWN) ? null : decimalValue.intValue();
        }
        return null;
    }
}