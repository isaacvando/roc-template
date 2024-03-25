interface CodeGen
    exposes [generate]
    imports [Parser.{ Node }]

generate : List Node -> Str
generate = \nodes ->
    body =
        nodes
        |> convertInterpolationsToText
        |> render
    """
    interface Pages
        exposes [page]
        imports []

    escapeHtml : Str -> Str
    escapeHtml = \\input ->
        input
        |> Str.replaceEach "&" "&amp;"
        |> Str.replaceEach "<" "&lt;"
        |> Str.replaceEach ">" "&gt;"
        |> Str.replaceEach "\\"" "&quot;"
        |> Str.replaceEach "'" "&#39;"

    page = \\model ->
    $(body)
    """

render = \nodes ->
    when List.map nodes nodeToStr is
        [elem] -> elem
        blocks ->
            list = blocks |> Str.joinWith ",\n"
            """
            [
            $(list)
            ]
            |> Str.joinWith ""
            """
            |> indent

nodeToStr = \node ->
    block =
        when node is
            Text t ->
                """
                \"""
                $(t)
                \"""
                """

            Conditional { condition, body } ->
                """
                if $(condition) then
                $(render body)
                else
                    ""
                """

            Sequence { item, list, body } ->
                """
                List.map $(list) \\$(item) ->
                $(render body)
                |> Str.joinWith ""
                """
    indent block

convertInterpolationsToText = \nodes ->
    List.map nodes \node ->
        when node is
            RawInterpolation i -> Text "\$($(i))"
            Interpolation i -> Text "\$($(i) |> escapeHtml)"
            Text t -> Text t
            Sequence { item, list, body } -> Sequence { item, list, body: convertInterpolationsToText body }
            Conditional { condition, body } -> Conditional { condition, body: convertInterpolationsToText body }
    |> List.walk [] \state, elem ->
        when (state, elem) is
            ([.. as rest, Text x], Text y) ->
                combined = Str.concat x y |> Text
                rest |> List.append combined

            _ -> List.append state elem

indent : Str -> Str
indent = \input ->
    Str.split input "\n"
    |> List.map \str ->
        Str.concat "    " str
    |> Str.joinWith "\n"
