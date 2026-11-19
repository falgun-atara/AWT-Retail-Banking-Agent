List<Contact> existingCustomers = [
    SELECT Id
    FROM Contact
    WHERE Email = 'jordan.hale@ascendbank.example'
    LIMIT 1
];
Contact customer;
if (existingCustomers.isEmpty()) {
    customer = new Contact(
        FirstName = 'Jordan',
        LastName = 'Hale',
        Email = 'jordan.hale@ascendbank.example',
        Birthdate = Date.newInstance(1988, 11, 3)
    );
    insert customer;
} else {
    customer = existingCustomers[0];
}

Integer cardCount = [SELECT COUNT() FROM Card__c WHERE Contact__c = :customer.Id];
if (cardCount == 0) {
    insert new List<Card__c>{
        new Card__c(
            Contact__c = customer.Id,
            Card_Type__c = 'Debit',
            Last_4_Digits__c = '4412',
            Status__c = 'Active'
        ),
        new Card__c(
            Contact__c = customer.Id,
            Card_Type__c = 'Credit',
            Last_4_Digits__c = '7780',
            Status__c = 'Blocked'
        )
    };
}

Id articleRecordTypeId = [
    SELECT Id
    FROM RecordType
    WHERE SobjectType = 'Knowledge__kav' AND DeveloperName = 'Base'
    LIMIT 1
].Id;

Map<String, Knowledge__kav> articlesByUrl = new Map<String, Knowledge__kav>{
    'lost-or-stolen-card' => new Knowledge__kav(
        Title = 'Lost or stolen card',
        UrlName = 'lost-or-stolen-card',
        Summary = 'Block a lost or stolen Ascend Bank card immediately. This assistant checks your registered email and date of birth, then shows the card type, last 4 digits, and status. It cannot unblock a card. If you also see a transaction you do not recognise, the card is blocked and the fraud team receives a summary. The assistant does not investigate the transaction.',
        Question__c = 'What should I do if my Ascend Bank card is lost or stolen?',
        Answer__c = 'If your Ascend Bank debit or credit card is lost or stolen, block it immediately. You can do that in this chat at any hour, in the Ascend Bank app, or at a branch. Before this assistant can see your cards or block one, it checks the email address and date of birth on your account. You will be shown the card type, the last 4 digits, and whether the card is Active or Blocked. If you have more than one card, say which card you mean. A block sets the card to Blocked and opens a support case with type Card Block. A blocked card cannot be used. This assistant cannot unblock a card. Unblocking is done in the Ascend Bank app or at a branch. Do not share the full card number. If you also notice a transaction you do not recognise, say so in the same chat. The assistant blocks the card and sends the fraud team a short summary. It does not look up or investigate the transaction. Questions about balances, transfers, and loans are handled by a specialist.',
        Language = 'en_US',
        RecordTypeId = articleRecordTypeId
    ),
    'replacement-card-timelines' => new Knowledge__kav(
        Title = 'Replacement card timelines',
        UrlName = 'replacement-card-timelines',
        Summary = 'Ascend Bank does not issue a replacement card in this chat. A standard replacement arrives by post in 5 to 7 business days. A branch can prepare one for collection on the next business day after the block if you bring photo identification. The blocked card stays blocked, and the replacement uses a new card number.',
        Question__c = 'How long does a replacement card take after my card is blocked?',
        Answer__c = 'After your card is blocked, this chat cannot order the replacement for you. A standard replacement card is sent by post and arrives in 5 to 7 business days. If you need it sooner, a branch can prepare a replacement for collection on the next business day after the block. Bring photo identification. The blocked card remains blocked. The replacement card has a new number, so only the last 4 digits of the new card are shown once it is issued. This assistant cannot unblock the old card and cannot change the postal timing. Ask a branch if you need a different delivery option. This is a timing guide, not financial or investment advice.',
        Language = 'en_US',
        RecordTypeId = articleRecordTypeId
    ),
    'reporting-fraud' => new Knowledge__kav(
        Title = 'Reporting fraud',
        UrlName = 'reporting-fraud',
        Summary = 'Tell this assistant about an unrecognised transaction in the same chat as a lost or stolen card. The assistant blocks the card and sends the fraud team a summary. It does not investigate the transaction. Share only the last 4 digits, never the full card number.',
        Question__c = 'How do I report a transaction I do not recognise?',
        Answer__c = 'If you see a transaction you do not recognise, say so when you report the lost or stolen card. This assistant will block the card and open a fraud report case that contains a short summary of what you said. The fraud team uses that summary. The assistant does not look up the transaction, explain it, or ask you to investigate it. Share only the last 4 digits of the card, never the full card number. You can also report fraud in the Ascend Bank app or at a branch. Balances, transfers, and loans are outside this assistant and are passed to a specialist.',
        Language = 'en_US',
        RecordTypeId = articleRecordTypeId
    )
};

Set<String> alreadyThere = new Set<String>();
for (Knowledge__kav row : [SELECT UrlName FROM Knowledge__kav WHERE UrlName IN :articlesByUrl.keySet()]) {
    alreadyThere.add(row.UrlName);
}
List<Knowledge__kav> toInsert = new List<Knowledge__kav>();
for (String urlName : articlesByUrl.keySet()) {
    if (!alreadyThere.contains(urlName)) {
        toInsert.add(articlesByUrl.get(urlName));
    }
}
if (!toInsert.isEmpty()) {
    insert toInsert;
    for (Knowledge__kav draft : [
        SELECT KnowledgeArticleId
        FROM Knowledge__kav
        WHERE Id IN :toInsert AND PublishStatus = 'Draft'
    ]) {
        KbManagement.PublishingService.publishArticle(draft.KnowledgeArticleId, true);
    }
}

List<Contact> mayaRows = [
    SELECT Id
    FROM Contact
    WHERE Email = 'maya.patel@example.com'
    LIMIT 1
];
Contact maya;
if (mayaRows.isEmpty()) {
    maya = new Contact(
        FirstName = 'Maya',
        LastName = 'Patel',
        Email = 'maya.patel@example.com',
        Birthdate = Date.newInstance(1991, 4, 18)
    );
    insert maya;
} else {
    maya = mayaRows[0];
}
Integer mayaCards = [SELECT COUNT() FROM Card__c WHERE Contact__c = :maya.Id AND Last_4_Digits__c = '4821'];
if (mayaCards == 0) {
    insert new Card__c(
        Contact__c = maya.Id,
        Card_Type__c = 'Debit',
        Last_4_Digits__c = '4821',
        Status__c = 'Active'
    );
}

System.debug('CUSTOMER=' + customer.Id);
System.debug('MAYA=' + maya.Id);
System.debug('CARDS=' + [SELECT COUNT() FROM Card__c WHERE Contact__c = :customer.Id]);
System.debug('ARTICLES=' + [SELECT COUNT() FROM Knowledge__kav WHERE UrlName IN :articlesByUrl.keySet() AND PublishStatus = 'Online']);
