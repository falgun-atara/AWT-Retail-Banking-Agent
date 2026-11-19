@IsTest
private class AscendCardAgentActionTest {
    @IsTest
    static void verifyMatchesEmailAndDateOfBirth() {
        Contact customer = customer('verify');
        insert customer;

        VerifyAscendCustomer.Request request = new VerifyAscendCustomer.Request();
        request.email = customer.Email;
        request.dateOfBirth = '03/11/1988';
        request.priorFailedAttempts = 1;

        VerifyAscendCustomer.Result result = VerifyAscendCustomer.execute(new List<VerifyAscendCustomer.Request>{ request })[0];

        System.assertEquals(true, result.verified);
        System.assertEquals(customer.Id, result.contactId);
        System.assertEquals(0.0, result.failedAttempts);
    }

    @IsTest
    static void verifyRejectsWrongDateWithoutSayingWhichField() {
        Contact customer = customer('reject');
        insert customer;

        VerifyAscendCustomer.Request request = new VerifyAscendCustomer.Request();
        request.email = customer.Email;
        request.dateOfBirth = '04/11/1988';
        request.priorFailedAttempts = 1;

        VerifyAscendCustomer.Result result = VerifyAscendCustomer.execute(new List<VerifyAscendCustomer.Request>{ request })[0];

        System.assertEquals(false, result.verified);
        System.assertEquals('', result.contactId);
        System.assertEquals(2.0, result.failedAttempts);
        System.assertEquals(
            'Those details do not match our records. Check the registered email and date of birth.',
            result.message
        );
    }

    @IsTest
    static void verifyRejectsBlankAndUnparseableDates() {
        VerifyAscendCustomer.Request blank = new VerifyAscendCustomer.Request();
        blank.email = 'missing@ascendbank.example';
        VerifyAscendCustomer.Result blankResult = VerifyAscendCustomer.execute(new List<VerifyAscendCustomer.Request>{ blank })[0];
        System.assertEquals(false, blankResult.verified);

        VerifyAscendCustomer.Request badDate = new VerifyAscendCustomer.Request();
        badDate.email = 'missing@ascendbank.example';
        badDate.dateOfBirth = 'not-a-date';
        VerifyAscendCustomer.Result badResult = VerifyAscendCustomer.execute(new List<VerifyAscendCustomer.Request>{ badDate })[0];
        System.assertEquals(false, badResult.verified);
        System.assertEquals('Enter the date of birth as DD/MM/YYYY.', badResult.message);
        System.assertEquals(0.0, badResult.failedAttempts);
        System.assertEquals(0, VerifyAscendCustomer.parseDates('31/02/1988').size());
        System.assertEquals(0, VerifyAscendCustomer.parseDates('November 3, 1988').size());
        System.assertEquals(0, VerifyAscendCustomer.parseDates('1988-11-03').size());
        System.assertEquals(0, VerifyAscendCustomer.parseDates('3/11/1988').size());
        System.assertEquals(1, VerifyAscendCustomer.parseDates('03/11/1988').size());
    }

    @IsTest
    static void verifyDoesNotCompareUntilDateIsDayMonthYear() {
        Contact customer = customer('format');
        insert customer;

        VerifyAscendCustomer.Request request = new VerifyAscendCustomer.Request();
        request.email = customer.Email;
        request.dateOfBirth = '1988-11-03';
        request.priorFailedAttempts = 1;

        VerifyAscendCustomer.Result result = VerifyAscendCustomer.execute(new List<VerifyAscendCustomer.Request>{ request })[0];

        System.assertEquals(false, result.verified);
        System.assertEquals('', result.contactId);
        System.assertEquals(1.0, result.failedAttempts);
        System.assertEquals('Enter the date of birth as DD/MM/YYYY.', result.message);
    }

    @IsTest
    static void listCardsReturnsTypeLastFourAndStatusOnly() {
        Contact customer = customer('list');
        insert customer;
        insert new List<Card__c>{
            card(customer.Id, 'Debit', '4412', 'Active'),
            card(customer.Id, 'Credit', '7780', 'Blocked')
        };

        GetAscendCustomerCards.Request request = new GetAscendCustomerCards.Request();
        request.contactId = customer.Id;
        GetAscendCustomerCards.Result result = GetAscendCustomerCards.execute(
            new List<GetAscendCustomerCards.Request>{ request }
        )[0];

        System.assertEquals(2, result.cardCount);
        System.assert(result.cardsSummary.contains('Debit ending 4412, Status Active'));
        System.assert(result.cardsSummary.contains('Credit ending 7780, Status Blocked'));
        System.assert(!result.cardsSummary.contains(customer.Id));

        GetAscendCustomerCards.Request missing = new GetAscendCustomerCards.Request();
        missing.contactId = 'not-an-id';
        System.assertEquals(0, GetAscendCustomerCards.execute(new List<GetAscendCustomerCards.Request>{ missing })[0].cardCount);
    }

    @IsTest
    static void blockSetsStatusAndOpensCardBlockAndFraudCases() {
        Contact customer = customer('block');
        insert customer;
        insert card(customer.Id, 'Debit', '4412', 'Active');

        BlockAscendCard.Request request = new BlockAscendCard.Request();
        request.contactId = customer.Id;
        request.last4 = '4412';
        request.cardType = 'debit card';
        request.unrecognisedTransactionSummary = 'A charge I do not recognise on card 4111111111114412.';

        BlockAscendCard.Result result = BlockAscendCard.execute(new List<BlockAscendCard.Request>{ request })[0];

        Card__c stored = [SELECT Status__c FROM Card__c WHERE Contact__c = :customer.Id AND Last_4_Digits__c = '4412'];
        System.assertEquals(true, result.success);
        System.assertEquals('Blocked', stored.Status__c);
        System.assert(!String.isBlank(result.blockCaseNumber));
        System.assert(!String.isBlank(result.fraudCaseNumber));

        Map<String, Case> casesByType = new Map<String, Case>();
        for (Case supportCase : [SELECT Type, Description FROM Case WHERE ContactId = :customer.Id]) {
            casesByType.put(supportCase.Type, supportCase);
        }
        System.assertEquals('Card Block', casesByType.get('Card Block').Type);
        System.assert(casesByType.get('Fraud Report').Description.contains('[redacted]'));
        System.assert(!casesByType.get('Fraud Report').Description.contains('4111111111114412'));
    }

    @IsTest
    static void blockAsksWhenSeveralCardsMatchAndRefusesUnblock() {
        Contact customer = customer('choice');
        insert customer;
        insert new List<Card__c>{
            card(customer.Id, 'Debit', '4412', 'Active'),
            card(customer.Id, 'Credit', '7780', 'Blocked')
        };

        BlockAscendCard.Request ambiguous = new BlockAscendCard.Request();
        ambiguous.contactId = customer.Id;
        BlockAscendCard.Result choice = BlockAscendCard.execute(new List<BlockAscendCard.Request>{ ambiguous })[0];
        System.assertEquals(true, choice.needsChoice);
        System.assertEquals(false, choice.success);

        BlockAscendCard.Request blocked = new BlockAscendCard.Request();
        blocked.contactId = customer.Id;
        blocked.last4 = '77-80';
        blocked.cardType = 'Credit';
        BlockAscendCard.Result already = BlockAscendCard.execute(new List<BlockAscendCard.Request>{ blocked })[0];
        System.assertEquals(true, already.alreadyBlocked);
        System.assertEquals(false, already.success);
        System.assert(already.message.contains('cannot unblock'));

        BlockAscendCard.Request missing = new BlockAscendCard.Request();
        missing.contactId = customer.Id;
        missing.last4 = '0000';
        System.assertEquals(false, BlockAscendCard.execute(new List<BlockAscendCard.Request>{ missing })[0].success);

        BlockAscendCard.Request badType = new BlockAscendCard.Request();
        badType.contactId = customer.Id;
        badType.cardType = 'prepaid';
        System.assert(BlockAscendCard.execute(new List<BlockAscendCard.Request>{ badType })[0].message.contains('Debit or Credit'));
    }

    @IsTest
    static void fraudReportCreatesCaseWithoutInvestigating() {
        Contact customer = customer('fraud');
        insert customer;

        CreateAscendFraudReport.Request request = new CreateAscendFraudReport.Request();
        request.contactId = customer.Id;
        request.summary = 'I do not recognise a charge.';
        request.last4 = '4412';
        request.cardType = 'Debit';
        CreateAscendFraudReport.Result result = CreateAscendFraudReport.execute(
            new List<CreateAscendFraudReport.Request>{ request }
        )[0];

        System.assertEquals(true, result.success);
        Case stored = [SELECT Type, Subject FROM Case WHERE ContactId = :customer.Id];
        System.assertEquals('Fraud Report', stored.Type);
        System.assert(stored.Subject.contains('Debit ending 4412'));

        CreateAscendFraudReport.Request blank = new CreateAscendFraudReport.Request();
        blank.contactId = customer.Id;
        System.assertEquals(false, CreateAscendFraudReport.execute(new List<CreateAscendFraudReport.Request>{ blank })[0].success);
    }

    @IsTest
    static void knowledgeSearchReturnsArticleTextAndHandlesAMiss() {
        RecordType recordType = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Knowledge__kav' AND DeveloperName = 'Base'
            LIMIT 1
        ];
        Knowledge__kav article = new Knowledge__kav(
            Title = 'Lost or stolen card',
            UrlName = 'ascend-card-test-lost-card',
            Summary = 'Block a lost card immediately.',
            Question__c = 'What if my card is lost or stolen?',
            Answer__c = '<p>Block it immediately and show only the last 4 digits.</p>',
            Language = 'en_US',
            RecordTypeId = recordType.Id
        );
        insert article;
        Test.setFixedSearchResults(new List<Id>{ article.Id });

        SearchAscendCardKnowledge.Request request = new SearchAscendCardKnowledge.Request();
        request.query = 'How do I handle a lost card?';
        SearchAscendCardKnowledge.Result found = SearchAscendCardKnowledge.execute(
            new List<SearchAscendCardKnowledge.Request>{ request }
        )[0];
        System.assertEquals(true, found.found);
        System.assert(found.knowledgeSummary.contains('Lost or stolen card'));
        System.assert(found.knowledgeSummary.contains('last 4 digits'));
        System.assert(!found.knowledgeSummary.contains('<p>'));

        SearchAscendCardKnowledge.Request empty = new SearchAscendCardKnowledge.Request();
        empty.query = 'ab';
        System.assertEquals(false, SearchAscendCardKnowledge.execute(new List<SearchAscendCardKnowledge.Request>{ empty })[0].found);
    }

    private static Contact customer(String token) {
        return new Contact(
            FirstName = 'Jordan',
            LastName = 'Hale ' + token,
            Email = 'jordan.' + token + '.' + String.valueOf(DateTime.now().getTime()) + '@ascendbank.example',
            Birthdate = Date.newInstance(1988, 11, 3)
        );
    }

    private static Card__c card(Id contactId, String cardType, String last4, String status) {
        return new Card__c(
            Contact__c = contactId,
            Card_Type__c = cardType,
            Last_4_Digits__c = last4,
            Status__c = status
        );
    }
}
