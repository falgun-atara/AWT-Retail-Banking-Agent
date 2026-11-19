/**
 * Confirms an Ascend Bank account holder by registered email and date of birth.
 * The date is compared only when it is entered as DD/MM/YYYY. A mismatch does not say which value was wrong.
 */
public with sharing class VerifyAscendCustomer {
    private static final String FORMAT_MESSAGE = 'Enter the date of birth as DD/MM/YYYY.';
    private static final String MISMATCH_MESSAGE = 'Those details do not match our records. Check the registered email and date of birth.';

    @InvocableMethod(
        label='Verify Ascend Customer'
        description='Matches a registered email and a date of birth entered as DD/MM/YYYY to one Contact. Does not reveal which value failed.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(verifyOne(req));
        }
        return results;
    }

    private static Result verifyOne(Request req) {
        Result result = new Result();
        Double prior = req == null || req.priorFailedAttempts == null ? 0 : req.priorFailedAttempts;
        result.verified = false;
        result.contactId = '';
        result.customerName = '';
        result.failedAttempts = prior;

        Date dateOfBirth = parseDob(req == null ? null : req.dateOfBirth);
        if (dateOfBirth == null) {
            result.message = FORMAT_MESSAGE;
            return result;
        }

        if (req == null || String.isBlank(req.email)) {
            result.failedAttempts = prior + 1;
            result.message = MISMATCH_MESSAGE;
            return result;
        }

        String email = req.email.trim();
        List<Contact> matches = [
            SELECT Id, Name, Birthdate
            FROM Contact
            WHERE Email = :email
            WITH USER_MODE
        ];

        List<Contact> verified = new List<Contact>();
        for (Contact candidate : matches) {
            if (candidate.Birthdate == dateOfBirth) {
                verified.add(candidate);
            }
        }

        if (verified.size() != 1) {
            result.failedAttempts = prior + 1;
            result.message = MISMATCH_MESSAGE;
            return result;
        }

        result.verified = true;
        result.failedAttempts = 0;
        result.contactId = verified[0].Id;
        result.customerName = verified[0].Name;
        result.message = 'Identity verified for ' + verified[0].Name + '.';
        return result;
    }

    @TestVisible
    private static Set<Date> parseDates(String raw) {
        Set<Date> dates = new Set<Date>();
        Date parsed = parseDob(raw);
        if (parsed != null) {
            dates.add(parsed);
        }
        return dates;
    }

    private static Date parseDob(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        Matcher formatted = Pattern.compile('(\\d{2})/(\\d{2})/(\\d{4})').matcher(raw.trim());
        if (!formatted.matches()) {
            return null;
        }
        Integer day = Integer.valueOf(formatted.group(1));
        Integer month = Integer.valueOf(formatted.group(2));
        Integer year = Integer.valueOf(formatted.group(3));
        if (month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
        }
        try {
            Date parsed = Date.newInstance(year, month, day);
            if (parsed.year() == year && parsed.month() == month && parsed.day() == day) {
                return parsed;
            }
        } catch (Exception ignored) {
            return null;
        }
        return null;
    }

    public class Request {
        @InvocableVariable(
            label='Email'
            description='Email address registered on the account'
            required=true
        )
        public String email;

        @InvocableVariable(
            label='Date of Birth'
            description='Date of birth as DD/MM/YYYY, for example 03/11/1988'
            required=true
        )
        public String dateOfBirth;

        @InvocableVariable(
            label='Prior Failed Attempts'
            description='How many failed verification attempts have already happened in this conversation'
            required=false
        )
        public Double priorFailedAttempts;
    }

    public class Result {
        @InvocableVariable(label='Verified' description='True only when email and date of birth match one Contact')
        public Boolean verified;

        @InvocableVariable(label='Contact Id' description='Contact Id when verified. Blank when verification fails.')
        public String contactId;

        @InvocableVariable(label='Customer Name' description='Contact name when verified. Blank when verification fails.')
        public String customerName;

        @InvocableVariable(label='Failed Attempts' description='Zero after a match. Otherwise the updated failed-attempt count.')
        public Double failedAttempts;

        @InvocableVariable(label='Message' description='Asks for DD/MM/YYYY when the date format is wrong. A mismatch does not say which detail was wrong.')
        public String message;
    }
}