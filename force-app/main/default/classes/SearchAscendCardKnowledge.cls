/**
 * Searches the three published Ascend Bank card articles.
 * Answers must come from the returned text.
 */
public with sharing class SearchAscendCardKnowledge {
    @InvocableMethod(
        label='Search Ascend Card Knowledge'
        description='Searches published articles about a lost or stolen card, replacement card timelines, and reporting fraud.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(searchOne(req));
        }
        return results;
    }

    private static Result searchOne(Request req) {
        Result result = new Result();
        result.found = false;
        String cleaned = req == null || req.query == null
            ? ''
            : req.query.replaceAll('[^A-Za-z0-9 ]', ' ').replaceAll('\\s+', ' ').trim();
        if (cleaned.length() < 3) {
            result.knowledgeSummary = 'No article matches that question.';
            return result;
        }

        List<Knowledge__kav> articles = searchArticles(cleaned);
        if (articles.isEmpty()) {
            result.knowledgeSummary = 'No article matches that question.';
            return result;
        }

        List<String> sections = new List<String>();
        for (Knowledge__kav article : articles) {
            sections.add(
                'Title: ' + article.Title
                + '\nSummary: ' + blankToEmpty(article.Summary)
                + '\nAnswer: ' + stripHtml(firstText(article.Answer__c, article.Question__c))
            );
        }
        result.found = true;
        result.knowledgeSummary = String.join(sections, '\n\n');
        return result;
    }

    private static List<Knowledge__kav> searchArticles(String cleaned) {
        String status = Test.isRunningTest() ? 'Draft' : 'Online';
        String soslTerm = String.escapeSingleQuotes(cleaned);
        String scope = Test.isRunningTest()
            ? 'UrlName LIKE \'ascend-card-test%\''
            : 'UrlName IN (\'lost-or-stolen-card\',\'replacement-card-timelines\',\'reporting-fraud\')';
        String sosl = 'FIND \'' + soslTerm + '\' IN ALL FIELDS RETURNING Knowledge__kav'
            + '(Title, Summary, Question__c, Answer__c, UrlName WHERE PublishStatus = \'' + status
            + '\' AND Language = \'en_US\' AND ' + scope + ' LIMIT 3)';
        List<Knowledge__kav> found = new List<Knowledge__kav>();
        try {
            List<List<SObject>> hits = Search.query(sosl, AccessLevel.USER_MODE);
            if (!hits.isEmpty()) {
                for (SObject row : hits[0]) {
                    found.add((Knowledge__kav) row);
                }
            }
        } catch (Exception ignored) {
            found.clear();
        }
        if (!found.isEmpty()) {
            return found;
        }
        return queryByWords(cleaned, status, scope);
    }

    private static List<Knowledge__kav> queryByWords(String cleaned, String status, String scope) {
        List<String> clauses = new List<String>();
        for (String word : cleaned.split('\\s+')) {
            if (word.length() <= 3 || clauses.size() == 3) {
                continue;
            }
            String token = '%' + String.escapeSingleQuotes(word) + '%';
            clauses.add(
                '(Title LIKE \'' + token + '\' OR Summary LIKE \'' + token + '\' OR Question__c LIKE \'' + token + '\')'
            );
        }
        if (clauses.isEmpty()) {
            return new List<Knowledge__kav>();
        }
        String soql = 'SELECT Title, Summary, Question__c, Answer__c, UrlName FROM Knowledge__kav'
            + ' WHERE PublishStatus = \'' + status + '\' AND Language = \'en_US\' AND ' + scope
            + ' AND (' + String.join(clauses, ' OR ') + ') LIMIT 3';
        return (List<Knowledge__kav>) Database.query(soql, AccessLevel.USER_MODE);
    }

    private static String firstText(String primary, String fallback) {
        return String.isBlank(primary) ? blankToEmpty(fallback) : primary;
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String stripHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim();
    }

    public class Request {
        @InvocableVariable(
            label='Query'
            description='The customer question about a lost or stolen card, a replacement card, or reporting fraud.'
            required=true
        )
        public String query;
    }

    public class Result {
        @InvocableVariable(label='Found' description='True when at least one card article matched.')
        public Boolean found;

        @InvocableVariable(
            label='Knowledge Summary'
            description='Text from the matching articles. Answer only from this text. When it says no article matches, say so.'
        )
        public String knowledgeSummary;
    }
}