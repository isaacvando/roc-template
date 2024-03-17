interface Parser
    exposes [parse, Node]
    imports []

Node a : [
    Text a,
    Interpolation a,
    Conditional { condition : a, body : a },
    For { list : a, item : a, body : a },
]

nodeMap : Node a, (a -> b) -> Node b
nodeMap = \node, mapper ->
    when node is
        Text val -> Text (mapper val)
        Interpolation val -> Interpolation (mapper val)
        Conditional { condition, body } -> Conditional { condition: mapper condition, body: mapper body }
        For { list, item, body } -> For { list: mapper list, item: mapper item, body: mapper body }

parse : Str -> { nodes : List (Node Str), args : List Str }
parse = \input ->
    bytesNodes = template { input: Str.toUtf8 input, val: [] }
    strNodes =
        bytesNodes
        |> List.map \node ->
            nodeMap node \bytes ->
                Str.fromUtf8 bytes |> unwrap

    args = parseArguments bytesNodes
    { nodes: strNodes, args }

Parser a : List U8 -> [Match { input : List U8, val : a }, NoMatch]

template = \state ->
    when interpolation state.input is
        Match { input, val } -> template { input, val: List.append state.val val }
        NoMatch ->
            when state.input is
                [] -> state.val
                [c, ..] ->
                    val =
                        when state.val is
                            [.. as r, Text t] ->
                                List.append r (Text (List.append t c))

                            _ -> List.append state.val (Text [c])
                    template { input: List.dropFirst state.input 1, val }

interpolation : Parser (Node (List U8))
interpolation = \in ->
    eatLineUntil = \state ->
        when state.input is
            ['}', '}', .. as rest] -> Match { input: rest, val: state.val }
            ['\n', _] -> NoMatch
            [c, .. as rest] -> eatLineUntil { input: rest, val: List.append state.val c }
            [] -> NoMatch

    when in is
        ['{', '{', .. as rest] ->
            eatLineUntil { input: rest, val: [] }
            |> map \state ->
                { input: state.input, val: Interpolation state.val }

        _ -> NoMatch

conditional : Parser (Node (List U8))
conditional = \in ->
    eatLineUntil = \state ->
        when state.input is
            ['|', '}', .. as rest] -> Match { input: rest, val: state.val }
            ['\n', _] -> NoMatch
            [c, .. as rest] -> eatLineUntil { input: rest, val: List.append state.val c }
            [] -> NoMatch

    when in is
        ['{', '|', 'i', 'f', ' ', .. as rest] ->
            eatLineUntil { input: rest, val: [] }
            |> map \state ->
                { input: rest, val: Conditional { condition: state.val, body: [] } }

        _ -> NoMatch

# Parsing functions

identifier : Parser (List U8)
identifier = \input ->
    when input is
        [c, ..] if 97 <= c && c <= 122 -> (chompWhile isAlphaNumeric) input
        _ -> NoMatch

chompWhile : (U8 -> Bool) -> Parser (List U8)
chompWhile = \predicate -> \input ->
        chomp = \parser ->
            when parser.input is
                [c, .. as rest] if predicate c -> chomp { input: rest, val: List.append parser.val c }
                _ -> parser

        chomp { input, val: [] } |> Match

isAlphaNumeric : U8 -> Bool
isAlphaNumeric = \c ->
    (48 <= c && c <= 57)
    || (65 <= c && c <= 90)
    || (97 <= c && c <= 122)

map : [Match a, NoMatch], (a -> b) -> [Match b, NoMatch]
map = \match, mapper ->
    when match is
        Match m -> Match (mapper m)
        NoMatch -> NoMatch

unwrap = \x ->
    when x is
        Err _ -> crash "bad unwrap"
        Ok v -> v

# Extract arguments

parseArguments : List (Node (List U8)) -> List Str
parseArguments = \ir ->
    List.walk ir (Set.empty {}) \args, node ->
        when node is
            Interpolation i -> args
            Text _ -> args
            Conditional _ -> args
            _ -> args
    |> Set.toList

getArgs : List U8 -> List Str
getArgs = \input ->
    getArgsHelp = \args, in ->
        when in is
            [_, .. as rest] ->
                when identifier in is
                    NoMatch -> getArgsHelp args rest
                    Match ident -> getArgsHelp (List.append args ident.val) ident.input

            _ -> args

    getArgsHelp [] input
    |> List.map \elem ->
        Str.fromUtf8 elem |> unwrap
