/**
 * Opens a fraud-report Case from the customer's summary.
 * Does not look up or investigate a transaction.
 */
public with sharing class CreateAscendFraudReport {
    @InvocableMethod(
        label='Create Ascend Fraud Report'
        description='Creates a Case with Type Fraud Report from a short customer summary. Does not investigate a transaction.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(createOne(req));
        }
        return results;
    }

    private static Result createOne(Request req) {
        Result result = new Result();
        result.success = false;
        result.caseNumber = '';

        Id contactId = toContactId(req == null ? null : req.contactId);
        String summary = redactDigits(req == null ? null : req.summary);
        if (contactId == null || String.isBlank(summary)) {
            result.message = 'A fraud report needs the verified customer and a short summary. Do not investigate the transaction.';
            return result;
        }

        String cardLabel = cardLabel(req);
        Case supportCase = new Case(
            ContactId = contactId,
            Type = 'Fraud Report',
            Subject = String.isBlank(cardLabel) ? 'Unrecognised transaction' : 'Unrecognised transaction — ' + cardLabel,
            Description = 'The customer reported an unrecognised transaction. The assistant did not investigate it. Summary: ' + summary,
            Origin = 'Web',
            Status = 'New',
            Priority = 'High'
        );
        insert as user supportCase;
        Case stored = [
            SELECT CaseNumber
            FROM Case
            WHERE Id = :supportCase.Id
            WITH USER_MODE
            LIMIT 1
        ];
        result.success = true;
        result.caseNumber = stored.CaseNumber;
        result.message = 'Fraud report ' + stored.CaseNumber + ' was sent to the fraud team.';
        return result;
    }

    private static String cardLabel(Request req) {
        String last4 = digitsOnly(req == null ? null : req.last4);
        String cardType = normalizeType(req == null ? null : req.cardType);
        if (last4.length() == 4 && cardType != null) {
            return cardType + ' ending ' + last4;
        }
        if (last4.length() == 4) {
            return 'card ending ' + last4;
        }
        return cardType;
    }

    private static String digitsOnly(String value) {
        return String.isBlank(value) ? '' : value.replaceAll('[^0-9]', '');
    }

    private static String normalizeType(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String text = value.toLowerCase();
        if (text.contains('debit')) {
            return 'Debit';
        }
        if (text.contains('credit')) {
            return 'Credit';
        }
        return null;
    }

    private static String redactDigits(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replaceAll('\\d{5,}', '[redacted]').trim();
    }

    private static Id toContactId(String value) {
        try {
            if (String.isBlank(value)) {
                return null;
            }
            Id parsed = (Id) value;
            return parsed.getSobjectType() == Contact.SObjectType ? parsed : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    public class Request {
        @InvocableVariable(
            label='Contact Id'
            description='Verified Contact Id. Bind this from the verification result, not from the customer message.'
            required=true
        )
        public String contactId;

        @InvocableVariable(
            label='Summary'
            description='Short summary of what the customer said about the unrecognised transaction. Do not add findings.'
            required=true
        )
        public String summary;

        @InvocableVariable(label='Last 4 Digits' description='Optional last 4 digits to mention on the case.' required=false)
        public String last4;

        @InvocableVariable(label='Card Type' description='Optional Debit or Credit label to mention on the case.' required=false)
        public String cardType;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when the Fraud Report case was created.')
        public Boolean success;

        @InvocableVariable(label='Case Number' description='Fraud Report case number. Blank when creation failed.')
        public String caseNumber;

        @InvocableVariable(label='Message' description='Customer-safe confirmation that the fraud team has the summary.')
        public String message;
    }
}