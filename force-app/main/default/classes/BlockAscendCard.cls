/**
 * Blocks one card for a verified customer and opens a Card Block case.
 * When the customer also reports an unrecognised transaction, opens a Fraud Report case.
 * Never changes a Blocked card back to Active.
 */
public with sharing class BlockAscendCard {
    @InvocableMethod(
        label='Block Ascend Card'
        description='Sets one matching card to Blocked and creates a Case with Type Card Block. Also creates a Fraud Report case when an unrecognised-transaction summary is supplied. Does not unblock a card.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(blockOne(req));
        }
        return results;
    }

    private static Result blockOne(Request req) {
        Result result = new Result();
        result.success = false;
        result.alreadyBlocked = false;
        result.needsChoice = false;
        result.blockCaseNumber = '';
        result.fraudCaseNumber = '';

        Id contactId = toContactId(req == null ? null : req.contactId);
        if (contactId == null) {
            result.message = 'Verify the customer before blocking a card.';
            return result;
        }

        String last4 = digitsOnly(req == null ? null : req.last4);
        if (!String.isBlank(req == null ? null : req.last4) && last4.length() != 4) {
            result.message = 'Use only the last 4 digits of the card.';
            return result;
        }
        String cardType = normalizeType(req == null ? null : req.cardType);
        if (!String.isBlank(req == null ? null : req.cardType) && cardType == null) {
            result.message = 'Say whether the card is Debit or Credit.';
            return result;
        }

        List<Card__c> owned = [
            SELECT Id, Card_Type__c, Last_4_Digits__c, Status__c
            FROM Card__c
            WHERE Contact__c = :contactId
            WITH USER_MODE
            ORDER BY Card_Type__c, Last_4_Digits__c
        ];

        List<Card__c> matches = new List<Card__c>();
        for (Card__c card : owned) {
            Boolean last4Matches = String.isBlank(last4) || card.Last_4_Digits__c == last4;
            Boolean typeMatches = String.isBlank(cardType) || card.Card_Type__c == cardType;
            if (last4Matches && typeMatches) {
                matches.add(card);
            }
        }

        if (matches.isEmpty()) {
            result.message = 'No card on this account matches that description.';
            return result;
        }
        if (matches.size() > 1) {
            result.needsChoice = true;
            result.message = 'More than one card matches. Ask which card, using only type and last 4 digits:\n' + describeCards(matches);
            return result;
        }

        Card__c card = matches[0];
        String summary = redactDigits(req == null ? null : req.unrecognisedTransactionSummary);
        if (card.Status__c == 'Blocked') {
            result.alreadyBlocked = true;
            result.message = 'The ' + card.Card_Type__c + ' card ending ' + card.Last_4_Digits__c
                + ' is already blocked. This assistant cannot unblock a card. Unblocking is done in the Ascend Bank app or at a branch.';
            if (!String.isBlank(summary)) {
                result.fraudCaseNumber = createCase(
                    contactId,
                    'Fraud Report',
                    'Unrecognised transaction — ' + card.Card_Type__c + ' ending ' + card.Last_4_Digits__c,
                    'The customer reported an unrecognised transaction. The card was already blocked. Summary: ' + summary
                );
                result.message += ' Fraud report ' + result.fraudCaseNumber + ' was sent to the fraud team. Do not investigate the transaction.';
            }
            return result;
        }

        card.Status__c = 'Blocked';
        update as user card;
        result.success = true;
        result.blockCaseNumber = createCase(
            contactId,
            'Card Block',
            'Card block — ' + card.Card_Type__c + ' ending ' + card.Last_4_Digits__c,
            'The customer requested an immediate block of the ' + card.Card_Type__c + ' card ending ' + card.Last_4_Digits__c + '.'
        );
        result.message = 'The ' + card.Card_Type__c + ' card ending ' + card.Last_4_Digits__c
            + ' is now blocked. Case ' + result.blockCaseNumber + ' was opened.';

        if (!String.isBlank(summary)) {
            result.fraudCaseNumber = createCase(
                contactId,
                'Fraud Report',
                'Unrecognised transaction — ' + card.Card_Type__c + ' ending ' + card.Last_4_Digits__c,
                'The customer reported a lost or stolen card and an unrecognised transaction. The card was blocked. The assistant did not investigate the transaction. Summary: ' + summary
            );
            result.message += ' Fraud report ' + result.fraudCaseNumber + ' was sent to the fraud team.';
        }
        return result;
    }

    private static String createCase(Id contactId, String caseType, String subject, String description) {
        Case supportCase = new Case(
            ContactId = contactId,
            Type = caseType,
            Subject = subject,
            Description = description,
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
        return stored.CaseNumber;
    }

    private static String describeCards(List<Card__c> cards) {
        List<String> lines = new List<String>();
        for (Card__c card : cards) {
            lines.add(card.Card_Type__c + ' ending ' + card.Last_4_Digits__c + ', Status ' + card.Status__c);
        }
        return String.join(lines, '\n');
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
            label='Last 4 Digits'
            description='Last 4 digits of the card to block. Leave blank only when the card type identifies one card.'
            required=false
        )
        public String last4;

        @InvocableVariable(
            label='Card Type'
            description='Debit or Credit. Leave blank only when the last 4 digits identify one card.'
            required=false
        )
        public String cardType;

        @InvocableVariable(
            label='Unrecognised Transaction Summary'
            description='Short summary of an unrecognised transaction, using the customer words. Leave blank when the customer did not report one. Do not investigate the transaction.'
            required=false
        )
        public String unrecognisedTransactionSummary;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when an Active card was set to Blocked.')
        public Boolean success;

        @InvocableVariable(label='Already Blocked' description='True when the matching card was already Blocked. It was not unblocked.')
        public Boolean alreadyBlocked;

        @InvocableVariable(label='Needs Choice' description='True when more than one card matches and nothing was changed.')
        public Boolean needsChoice;

        @InvocableVariable(label='Block Case Number' description='Case number for the Card Block case. Blank when no block case was created.')
        public String blockCaseNumber;

        @InvocableVariable(label='Fraud Case Number' description='Case number for the Fraud Report case. Blank when no fraud report was created.')
        public String fraudCaseNumber;

        @InvocableVariable(label='Message' description='Customer-safe result. Card details are limited to type, last 4 digits, and status.')
        public String message;
    }
}