/**
 * Lists an account holder's cards using only type, last 4 digits, and status.
 */
public with sharing class GetAscendCustomerCards {
    @InvocableMethod(
        label='Get Ascend Customer Cards'
        description='Returns the verified customer cards as type, last 4 digits, and status. Never returns a full card number.'
    )
    public static List<Result> execute(List<Request> requests) {
        Set<Id> contactIds = new Set<Id>();
        for (Request req : requests) {
            Id contactId = toContactId(req == null ? null : req.contactId);
            if (contactId != null) {
                contactIds.add(contactId);
            }
        }

        Map<Id, List<Card__c>> cardsByContact = new Map<Id, List<Card__c>>();
        if (!contactIds.isEmpty()) {
            for (Card__c card : [
                SELECT Contact__c, Card_Type__c, Last_4_Digits__c, Status__c
                FROM Card__c
                WHERE Contact__c IN :contactIds
                WITH USER_MODE
                ORDER BY Card_Type__c, Last_4_Digits__c
            ]) {
                if (!cardsByContact.containsKey(card.Contact__c)) {
                    cardsByContact.put(card.Contact__c, new List<Card__c>());
                }
                cardsByContact.get(card.Contact__c).add(card);
            }
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result result = new Result();
            Id contactId = toContactId(req == null ? null : req.contactId);
            if (contactId == null) {
                result.cardCount = 0;
                result.cardsSummary = 'No cards are on file for this customer.';
                results.add(result);
                continue;
            }
            List<Card__c> cards = cardsByContact.containsKey(contactId)
                ? cardsByContact.get(contactId)
                : new List<Card__c>();
            result.cardCount = cards.size();
            result.cardsSummary = cards.isEmpty()
                ? 'No cards are on file for this customer.'
                : describeCards(cards);
            results.add(result);
        }
        return results;
    }

    private static String describeCards(List<Card__c> cards) {
        List<String> lines = new List<String>();
        for (Card__c card : cards) {
            lines.add(card.Card_Type__c + ' ending ' + card.Last_4_Digits__c + ', Status ' + card.Status__c);
        }
        return String.join(lines, '\n');
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
    }

    public class Result {
        @InvocableVariable(label='Card Count' description='How many cards belong to this customer.')
        public Integer cardCount;

        @InvocableVariable(
            label='Cards Summary'
            description='One line per card: type, last 4 digits, and status. This is the only card detail that may be shown.'
        )
        public String cardsSummary;
    }
}