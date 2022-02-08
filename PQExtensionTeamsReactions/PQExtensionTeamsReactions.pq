// This file contains your Data Connector logic
section PQExtensionTeamsReactions;

[DataSource.Kind="PQExtensionTeamsReactions", Publish="PQExtensionTeamsReactions.Publish"]
shared PQExtensionTeamsReactions.Contents = Value.ReplaceType(PQExtensionTeamsReactionsImpl, PQExtensionTeamsReactionsType);

[DataSource.Kind="PQExtensionTeamsReactions", Publish="PQExtensionTeamsReactions.PublishDetails"]
shared PQExtensionTeamsReactions.DetailsContents = Value.ReplaceType(PQExtensionTeamsReactionsImplDetails, PQExtensionTeamsReactionsType);

// Data Source Kind description <https://github.com/microsoft/DataConnectors/blob/master/docs/m-extensions.md>
PQExtensionTeamsReactions = [
    Authentication = [
        Aad = [
            AuthorizationUri = "https://login.microsoftonline.com/common/oauth2/authorize",
            Resource = "https://graph.microsoft.com" // Azure AD resource value for your service - Guid or URL
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel") // (optional Friendly display name for this extension in credential dialogs.         
    // , TestConnection    Gateway 経由でデータ更新する場合にはサポート必要
];

// Data Source UI publishing description
PQExtensionTeamsReactions.Publish = [
    Beta = false,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = PQExtensionTeamsReactions.Icons,
    SourceTypeImage = PQExtensionTeamsReactions.Icons
];

PQExtensionTeamsReactions.PublishDetails = [
    Beta = false,
    Category = "Other",
    ButtonText = { Extension.LoadString("FormulaTitle"), Extension.LoadString("FormulaHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = PQExtensionTeamsReactions.Icons,
    SourceTypeImage = PQExtensionTeamsReactions.Icons
];

PQExtensionTeamsReactions.Icons = [
    Icon16 = { Extension.Contents("PQExtensionTeamsReactions16.png"), Extension.Contents("PQExtensionTeamsReactions20.png"), Extension.Contents("PQExtensionTeamsReactions24.png"), Extension.Contents("PQExtensionTeamsReactions32.png") },
    Icon32 = { Extension.Contents("PQExtensionTeamsReactions32.png"), Extension.Contents("PQExtensionTeamsReactions40.png"), Extension.Contents("PQExtensionTeamsReactions48.png"), Extension.Contents("PQExtensionTeamsReactions64.png") }
];

teamIds2responses = (groupId as text, channelId as text, beforeDays as number) as table  =>
let
    targetUrl = "https://graph.microsoft.com/beta/teams/" & groupId & "/channels/" & channelId & "/messages",
    targetDate = Date.AddDays(DateTime.FixedLocalNow(), -beforeDays),
    getMessages = (url as text)  =>
        let
            currentJson = Json.Document(Web.Contents(url)),
            hasLink = Record.HasFields(currentJson, "@odata.nextLink"),
            nextLink = if hasLink then currentJson[#"@odata.nextLink"] else null,
            currentCount = currentJson[#"@odata.count"],
            createdDateTime = currentJson[value]{currentCount - 1}[createdDateTime],
            createdDateValue = DateTime.FromText(createdDateTime),
            jsonLists = List.Transform(currentJson[value], each 
            hasFinished = targetDate > createdDateValue or (not hasLink),
                 [
                    onBehalfOf = if _[onBehalfOf] is null then null else _[onBehalfOf][user],
                    postUser =  if _[from] is null then null else _[from][user],
                    reactions = if _[reactions] is null then null else List.Transform( _[reactions], each 
                    [
                        reactionType = _[reactionType],
                        createdDateTime = DateTime.FromText(_[createdDateTime]),
                        user = if _[user] is null then null else _[user][user]
                    ] ),
                    link = _[webUrl]
                ]
            ),
            jsonTable = Table.FromList(
                jsonLists,
                Record.FieldValues,
                type table [
                    onBehalfOf = nullable [
                            id = text,
                            displayName = nullable text,
                            userIdentityType = text
                        ],
                    postUser = nullable [
                            id = text,
                            displayName = nullable text,
                            userIdentityType = text
                        ],
                    reactions= nullable {[
                        reactionType = text,
                        createdDateTime = datetime,
                        user = nullable [
                            id = text,
                            displayName = nullable text,
                            userIdentityType = text
                        ]
                    ]},
                    link = text
                ]
            ),
            results = if hasFinished then jsonTable else Table.Combine({jsonTable, @getMessages(nextLink)})
        in
            results,
    responses = getMessages(targetUrl)
in
    responses;

shared PQExtensionTeamsReactions.Matches = (expression as text, optional original as text, optional indexBeginWith1 as number ) as text =>
let
    originalText = Text.Combine({original, ""}),
    expressionText = Text.Replace(expression, "\", "\\"),
    replaceResult =  Web.Page("<script>var originalText="&"'"&originalText&"'"&";var expression=new RegExp('"&expressionText&"','g');var result=originalText.match(expression);document.write(result);</script>")
        [Data]{0}[Children]{0}[Children],

    result = if (indexBeginWith1 = null) then {
        replaceResult{1}[Text]{0} as text 
    } else {
        let
            matches = Text.Split(replaceResult{1}[Text]{0}, ","),
            safeIndex = if (indexBeginWith1 <= 0 or indexBeginWith1 > List.Count(matches)) then 0 else indexBeginWith1 - 1 
        in 
            matches{safeIndex} as text
    }
in 
    result{0};

shared PQExtensionTeamsReactions.Replace = (expression as text, optional original as text,  optional replacement as text) as text =>
let
    originalText = Text.Combine({original, ""}),
    expressionText = Text.Replace(expression, "\", "\\"),
    replaceText = Text.Combine({replacement, ""}),
    replaceResult =  Web.Page("<script>var originalText="&"'"&originalText&"'"&";var replacement="&"'"&replaceText&"'"&";var expression=new RegExp('"&expressionText&"','g');var result=originalText.replace(expression,replacement);document.write(result);</script>")
      [Data]{0}[Children]{0}[Children],

    result = if (List.Count(replaceResult) <= 1) then { 
      "" as text // 変換して何も残らない場合
    } else if (replaceResult{1}[Text]{0} = null) then {
      originalText   as text// 何も見つからない場合
    } else {
      replaceResult{1}[Text]{0} as text
    }
in 
    result{0};

PQExtensionTeamsReactionsType = type function (
    teamsChannelUrl as (type text meta [
        Documentation.FieldCaption = "Teams Channel URL",
        Documentation.FieldDescription = "Text, 解析したい Channle の 「リンクをコピー」を貼り付け",
        Documentation.SampleValues = {"https://teams.microsoft.com/l/message/19:c5ec08edfee44d3dbaed17b8c163462d@thread.tacv2/1636637502465?tenantId=7f8d27e7-be70-4bed-83d5-97be9ab7e711&groupId=a70cc9a6-85a4-4b73-974a-c005f11ca2b5&parentMessageId=1636637502465&teamName=TestForTeams&channelName=%E4%B8%80%E8%88%AC&createdTime=1636637502465"}
    ]),
    optional daysBefore as (type number meta [
        Documentation.FieldCaption = "days before",
        Documentation.FieldDescription = "何日前からの集計か？ デフォルトは 30日",
        Documentation.SampleValues = { 100, 60, 7 }
    ]))
    as list meta [
        Documentation.Name = "Teams Reactions の解析",
        Documentation.LongDescription = "解析したい Channel の「リンクをコピー」を貼り付けて見ましょう。",
        Documentation.Examples = {[
            Description = "Returns error message with invalid Forms URL not including TeamId and ChannelId",
            Code = "PQExtensionTeamsReactions.Contents(""invalid url"")",
            Result = "{ ""URL に ""groupId="" が含まれていませんでした。""}"
        ],[
            Description = "Returns valid responses!",
            Code = "PQExtensionTeamsReactions.Contents(""https://teams.microsoft.com/l/message/19:c5ec08edfee44d3dbaed17b8c163462d@thread.tacv2/1636637502465?tenantId=7f8d27e7-be70-4bed-83d5-97be9ab7e711&groupId=a70cc9a6-85a4-4b73-974a-c005f11ca2b5&parentMessageId=1636637502465&teamName=TestForTeams&channelName=%E4%B8%80%E8%88%AC&createdTime=1636637502465"")",
            Result = "{ [
                onBehalfOf = null,
                user = null,
                reactions = null
            ]}"
        ]}
    ];

PQExtensionTeamsReactionsImplDetails = (teamsChannelUrl as text, optional daysBefore as number) =>
    let
        _groupId =Text.Replace(PQExtensionTeamsReactions.Matches("groupId=[^&]+", teamsChannelUrl), "groupId=", ""),
        _channelId =Text.Replace(PQExtensionTeamsReactions.Matches("message/[^\/]+", teamsChannelUrl), "message/", ""),
        _daysBefore = if daysBefore is null then 30 else daysBefore,
        _message = teamIds2responses(_groupId, _channelId, _daysBefore)
    in
        _message ;
        
PQExtensionTeamsReactionsImpl = (teamsChannelUrl as text, optional daysBefore as number) =>
    let
        _groupId =Text.Replace(PQExtensionTeamsReactions.Matches("groupId=[^&]+", teamsChannelUrl), "groupId=", ""),
        _channelId =Text.Replace(PQExtensionTeamsReactions.Matches("message/[^\/]+", teamsChannelUrl), "message/", ""),
        _daysBefore = if daysBefore is null then 30 else daysBefore,
        _responses = teamIds2responses(_groupId, _channelId, _daysBefore),
        _reactionsExpanded = Table.ExpandListColumn(_responses, "reactions"),
        _exceptedNoReactions = Table.SelectRows(_reactionsExpanded, each ([reactions] <> null)),
        _postUserExpanded = Table.ExpandRecordColumn(_exceptedNoReactions, "postUser", {"id", "displayName", "userIdentityType"}, {"id", "displayName", "userIdentityType"}),
        _reactionTypeExpanded = Table.ExpandRecordColumn(_postUserExpanded, "reactions", {"reactionType"}, {"reactionType"}),
        _counts = Table.Group(_reactionTypeExpanded, {"displayName", "reactionType"}, {{"カウント", each Table.RowCount(_), Int64.Type}})
in
        _counts ;


