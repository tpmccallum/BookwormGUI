windowLoaded = $.Deferred()
optionsLoaded = $.Deferred()

class xOption
    # An option for the x-axis (Publishing year, Author age, etc.)
    constructor: (name, val, unit, range) ->
        @name = name
        @val = val
        @unit = unit
        @range = range

class yOption
    # An option for the y-axis (Percentage of texts, Words per million, etc.)
    constructor: (name, val) ->
        @name = name
        @val = val

class ColorManager
    # Manages query colors
    constructor: () ->
        # "#31a354", "#fd8d3c",
        @defaultColors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf"]
        @colors = @defaultColors.slice(0)
        @id = 0

    # Call to get a new color for a query
    getColor: () ->
        console.log @colors
        if @colors.length == 0 then "#999999" else @colors.shift()

    # Call to return a color from a query being removed
    returnColor: (color) ->
        @colors.unshift(color) if !(color in @colors)

class MetaField

    constructor: (name, id, values) ->
        @name = name
        @id = id
        @values = values

class MetaValue

    constructor: (name, id) ->
        @name = name
        @id = id

class Filter
    # A metadata filter, constraining the query to the corpus with field==value
    constructor: (field, value) ->
        @field = field
        @value = value

class Query
    # A single ngram query, including any metadata filters
    constructor: (ngram, filters, colorManager) ->
        @ngram = ngram
        @filters = filters
        @colorManager = colorManager
        @color = @colorManager.getColor()
        @id = @colorManager.id++

    # Call this when removing the query
    destroy: () =>
        @colorManager.returnColor(@color)

class State
    # The internal state of the app, including all queries
    constructor: (db, x, smoothing=4, caseSensitive=false) ->
        @state = "loading"
        @database = db
        @queries = []
        @smoothing = smoothing
        @caseSensitive = caseSensitive
        @xAxis = x
        @yAxis = new yOption "per million words", "Occurrences_per_Million_Words"
        @xRange = x.range
        @data = []

    changeState: (newState) ->
        return if @state == newState

    # Given a query id, return that query's index in the @queries array
    getQueryIndex: (id) =>
        (i for query, i in @queries when query.id == id)[0]

    # Add a query to the internal state (only called on init)
    addQuery: (query) =>
        @queries.push query

    # Duplicate a currently-existing query, add it to the internal state, and return it
    duplicateQuery: (query) ->
        newQuery = new Query query.ngram, (f for f in query.filters), query.colorManager
        i = @getQueryIndex query.id
        @queries.splice(i+1, 0, newQuery)
        newQuery

    # Remove a query from the internal state
    removeQuery: (query) ->
        query.destroy()
        @queries.splice $.inArray(query, @queries), 1

class APIManager
    constructor: () ->

    parseState: (state) ->
        "Parses an internal state into the API format and returns it"
        limits = []
        for query in state.queries
            limit =
                word: [query.ngram]
            limit[state.xAxis.val] =
                    "$gt": state.xRange[0]
                    "$lt": state.xRange[1]
            for filter in query.filters
                if limit[filter.field.id]? then limit[filter.field.id].push filter.value.id else limit[filter.field.id] = [filter.value.id]
            limits.push limit
        queryBundle =
            search_limits: limits
            counttype: state.yAxis.val
            words_collation: if state.caseSensitive then "Case_Sensitive" else "Case_Insensitive"
            smoothingSpan: state.smoothing
            database: state.database
            method: "return_query_values"
            groups: [state.xAxis.val]
        queryBundle

    parsePoint: (state, point) ->

    processCounts: (state, counts) ->
        "Processes the counts into highcharts-readable format"
        counts = eval counts.split('===RESULT===')[1]
        data = []
        if state.xAxis.unit == "year"
            for series, i in counts
                data.push
                    name: series.Name
                    data: [Date.UTC(k, 0, 1), v] for k,v of series.values
                    color: state.queries[i].color
                    id: state.queries[i].id
        else if state.xAxis.unit == "month"
            for series, i in counts
                data.push
                    name: series.Name
                    data: [Date.UTC(-1, 12, k), v] for k,v of series.values
                    color: state.queries[i].color
                    id: state.queries[i].id
        else
            for series, i in counts
                data.push
                    name: series.Name
                    data: [parseInt(k), v] for k,v of series.values
                    color: state.queries[i].color
                    id: state.queries[i].id
        data

    getCounts: (state) ->
        "Gets the ngram counts for the given internal state"
        $.ajax
            url: '/cgi-bin/dbbindings.py'
            data:
                queryTerms: JSON.stringify(@parseState state)

    getTexts: (state, point) ->
        "Gets a random sample of texts for a particular point"
        $.ajax
            url: '/cgi-bin/dbbindings.py'
            data:
                queryTerms: JSON.stringify(@parsePoint state, point)

    getOptions: () ->
        "Gets the front-end options"
        $.ajax
            url: 'static/options/options.json'

    processOptions: (options, colorManager) ->
        o = 
            settings: options["settings"]
            xOptions: (new xOption(x.name, x.dbfield, x.unit, x.range) for x in options["ui_components"] when x.type is "time")
            metadata: []
            queries: []

        metadata = (x for x in options["ui_components"] when x.type is "categorical")
        for meta in metadata
            des = meta["categorical"]["descriptions"]
            values = (new MetaValue((if des[v].shortname? then des[v].shortname else des[v].name), des[v].dbcode) for v in meta["categorical"]["sort_order"])
            o.metadata.push new MetaField(meta.name, meta.dbfield, values)


        initial = options["default_search"][Math.floor(Math.random()*options["default_search"].length)]
        for search in initial["search_limits"]
            filters = []
            for field, value of search
                if field != "word"
                    metafield = x for x in o.metadata when x.id is field
                    metavalue = x for x in metafield.values when x.id is value[0]
                    filters.push (new Filter metafield, metavalue)
            o.queries.push(new Query search["word"][0], filters, colorManager)

        o


class UIManager
    # Handles anything that involves rendering to the DOM
    constructor: (bookworm, state, xOptions) ->
        @bookworm = bookworm
        @state = state

        # Render the initial queries to the DOM
        for query in state.queries
            $("#meta .queries").append(@getQueryHtml query)

        $(".smoothing .no").text(@state.smoothing)

        $("#smoothing").slider
            min: 0,
            max: 14,
            value: 4,
            slide: (event, ui) =>
                @state.smoothing = @smoothingUnits ui.value
                $(".smoothing .no").text @state.smoothing
                $("#meta").click()
                console.log $("#meta")

        # Click binding for the Info link
        $(".link.info").click () =>
            @dialog("Bookworm is a collaboration between the Harvard Cultural Observatory, Open Library, and the Open Science Data Cloud. It enables you to graphically explore lexical trends across a huge digital library.", "Information")

        # TODO: clean up this section
        $(document).on "click", "#meta .queries .query .filter", (event) =>
            target = $(event.target)
            i = @state.getQueryIndex target.data("query-id")
            query = @state.queries[i]

            meta = $($("#meta .queries .query")[i]).find(".metadata-selection").html(@getMetaHtml query)

            $(".chzn-select").chosen()
            $(".chzn-select").each () ->
                $(@).data("chosen-values", $(@).val())
            $(".chzn-select").change (e) =>
                field = $(e.target)
                o = if (field.data "chosen-values")? then (field.data "chosen-values") else []
                n = if field.val()? then field.val() else []

                if query.filters.length == 0
                    $($("#meta .queries .query")[i]).find(".filter").remove()

                if o.length > n.length
                    deleted = _.difference(o, n)[0]
                    filter = (x for x in query.filters when x.value.id+"" == deleted+"")[0]
                    iF = query.filters.indexOf(filter)
                    query.filters.splice iF, 1

                    if query.filters.length == 0
                        $("<span />").text("All").addClass("filter").appendTo($($("#meta .queries .query")[i]).children(".filters"))

                    $(f).remove() for f in $($($("#meta .queries .query")[i]).find(".filter")) when $(f).data("query-id") == query.id and $(f).data("field-id")+"" == filter.field.id+"" and $(f).data("value-id")+"" == filter.value.id+""

                else if o.length < n.length
                    added = _.difference(n, o)[0]
                    f = x for x in @bookworm.metadata when x.id+"" == field.data("id")
                    v = x for x in f.values when x.id+"" == added+""
                    filter = new Filter(f, v)
                    query.filters.push filter

                    $("<span />").text(filter.value.name).addClass("filter").data("field-id", filter.field.id)
                        .data("value-id", filter.value.id).data("query-id", query.id).appendTo($($("#meta .queries .query")[i]).children(".filters"))

                field.data "chosen-values", n

            fc = $("<div />").addClass("clear").appendTo(meta)
            meta.children(".metadata").fadeIn 200
            fc.show()
            fc.click () =>
                fc.remove()
                meta.children(".metadata").fadeOut 200

    smoothingUnits: (val) -> [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 18, 24, 36][val]

    setName: (name) ->
        $(".header .title .current").text(name)

    addXOption: (xOption) ->
        $("<div />").addClass("option").text(xOption.name).appendTo($(".x-axis .dropdown"))

    selectXOption: (xOption) ->
        $("#chart .x-axis .label").text(xOption.name)
        $("#full-clear").click()

    showXOptions: () ->
        $("#chart .x-axis .dropdown, #full-clear").show()
        $("#full-clear").click () =>
            $("#chart .x-axis .dropdown, #full-clear").hide()
            $("#full-clear").unbind "click"

    getMetaHtml: (query) ->
        html = $("<div />").addClass("metadata")
        for field in @bookworm.metadata
            m = $("<div />").addClass("field")
            $("<div />").addClass("label").text(field.name).appendTo(m)
            values = $("<select multiple />").addClass("values chzn-select").attr("data-placeholder", "All")
                .data("name", field.name).data("id", field.id)
            for value in field.values
                v = $("<option />").addClass("values").html(value.name).val(value.id)
                v.attr('selected', 'selected') if (x for x in query.filters when (x.field.id == field.id and x.value.id == value.id)).length != 0
                v.appendTo(values)
            values.appendTo(m)
            m.appendTo(html)
        html

    getQueryHtml: (query) ->
        "Returns the HTML for a query"
        
        html = $("<div />").addClass("query").attr("data-id", query.id)
        $("<span />").addClass("color").css("background-color", query.color).appendTo(html)
        $("<input />").val(query.ngram).addClass("ngram").appendTo(html).change (e) =>
            query.ngram = $(e.target).val()
        $("<span />").text("in").addClass("in").appendTo(html)
        filters = $("<div />").addClass("filters")
        $("<div />").addClass("metadata-selection").appendTo(filters)
        if query.filters.length == 0
            $("<span />").text("All texts").addClass("filter").appendTo(filters)
        else
            for filter in query.filters
                $("<span />").text(filter.value.name).addClass("filter").data("field-id", filter.field.id)
                    .data("value-id", filter.value.id).data("query-id", query.id).appendTo(filters)

        filters.appendTo(html)
        $("<span />").text("47B words").addClass("corpus").appendTo(html)

        # Click event for duplicating the query
        $("<span />").html("+").addClass("add").appendTo(html).click (e) =>
            newQuery = @state.duplicateQuery query
            html.after @getQueryHtml(newQuery).hide()
            html.next().slideDown 200, () -> $(@).css("overflow", "visible")

        # Click event for removing the query
        $("<span />").html("&times;").addClass("remove").appendTo(html).click (e) =>
            if @state.queries.length != 1
                @state.removeQuery query
                html.slideUp 200, -> @.remove()
        html

    coverChart: () ->
        "Partially covers the chart with the 'click to refresh' message"

        $("#chart .cover").fadeIn 200

    hideChart: () ->
        "Completely covers the chart"

        $("#meta .query input").blur()
        $("#chart .cover").stop().delay(100).fadeOut 200
        $("#chart .white").stop().fadeIn 200

    showChart: () ->
        "Completely uncovers the chart"

        $("#chart .white").stop().fadeOut 200
        $("#chart .cover").stop().fadeOut 200

    toggleCase: () ->
        "Toggles the visibility of the 'in' part of Case (in)sensitivity"

        $("#meta .settings .case .in").animate
            width: "toggle"
        , 150
            
    dialog: (text, title=null, width=400) ->
        "Generates and renders a dialog box containing text and optionally a title"

        dialog = $("<div />").addClass("dialog")
        $("<div />").addClass("clear").appendTo(dialog)
        box = $("<div />").addClass("box").width(width)
        $("<div />").addClass("title").text(title).appendTo(box)
        $("<div />").addClass("x").html("&times;").appendTo(box)
        $("<div />").addClass("text").text(text).appendTo(box)
        box.appendTo(dialog)

        # Click events to close the dialog
        dialog.find(".clear").click () ->
            $(@).parent().fadeOut(200, () -> $(@).remove())
        dialog.find(".x").click () ->
            $(@).parent().parent().fadeOut(200, () -> $(@).remove())

        dialog.hide().appendTo($("#dialog")).fadeIn(200)

    toggleResetZoom: (enable) ->
        if enable
            $("#reset-zoom").fadeIn 200
        else
            $("#reset-zoom").fadeOut 200

class Chart
    constructor: (data, bookworm, chartContainer="highchart") ->
        @bookworm = bookworm
        @chartContainer = chartContainer
        @chart = new Highcharts.Chart
            chart:
                marginBottom: 70
                marginLeft: 70
                marginRight: 30
                marginTop: 10
                animation: true
                renderTo: @chartContainer
                zoomType: 'x'
                type: 'line'
                backgroundColor: 'rgba(0,0,0,0)'
                events:
                    selection: (event) =>
                        event.preventDefault()
                        @chart.xAxis[0].setExtremes(event.xAxis[0].min, event.xAxis[0].max)
                        bookworm.uiManager.toggleResetZoom true
            title:
                text: null
            exporting:
                width: 800
                buttons: {}
            lineWidth: 1
            xAxis: 
                type: 'datetime'
                title:
                    text: null
                lineWidth: 1
                lineColor: "#CCC"
                gridLineWidth: 0
                labels:
                    style:
                        color: "#666"
                        fontFamily: "Open Sans"
            yAxis: 
                title:
                    text: null
                lineWidth: 1
                lineColor: '#CCC'
                tickColor: '#CCC'
                min: 0
                gridLineWidth: 0
                endOnTick: false
                labels:
                    style:
                        color: "#666"
                        fontFamily: "Open Sans"
            tooltip:
                useHTML: true
                borderRadius: 1
                borderWidth: 1
                borderColor: "#999"
                shadow: false
                shared: true
                crosshairs: [
                    color: "#eee"
                ]
                # positioner: (w, h, p) ->
                #     {x: p.plotX, y: p.plotY}
                style:
                    color: "#333"
                    fontSize: "11px"
                    padding: 12
                    fontFamily: "Open Sans"
                formatter: () ->
                    # str = '<b>'+Highcharts.dateFormat('%B %Y', this.points[0].x)+'</b><br/>'
                    if bookworm.state.xAxis.unit == "year"
                        str = '<b>'+Highcharts.dateFormat('%Y', this.points[0].x)+'</b><br/>'
                    else if bookworm.state.xAxis.unit == "month"
                        str = '<b>'+Highcharts.dateFormat('%B %Y', this.points[0].x)+'</b><br/>'
                    else if bookworm.state.xAxis.unit == "day"
                        str = '<b>'+Highcharts.dateFormat('%B %e, %Y', this.points[0].x)+'</b><br/>'
                    else
                        str = '<b>'+Highcharts.numberFormat(this.points[0].x, 0)+'</b><br/>'
                    for k,v of this.points
                        str += '<div class="color" style="background-color: '+v.series.color+';"></div>'+v.series.name+': '+v.y+"<br/>"
                    return str
            legend:
                enabled: false
            series: data
            plotOptions:
                line:
                    animation: true
                    shadow: false
                    lineWidth: 1.5
                    marker: 
                        enabled: false
                        symbol: 'circle'
                        radius: 3
                    states:
                        hover:
                            lineWidth: 2.5
                            marker:
                                enabled: true
                series:
                    cursor: 'pointer'
                    turboThreshold: 1500
                    events:
                        click: null
            point: {}
            exporting:
                buttons:
                    exportButton:
                        enabled: false
                        menuItems: [
                            text: 'Export to PNG'
                            onclick: () ->
                                this.exportChart
                                    width: 800
                                    height: 600
                        ,
                            text: 'Export raw data'
                            onclick: () ->
                                $("#export-data .results").text(currentData)
                                makeOverlay($("#export-data"))
                        ,
                        null,
                        null
                        ]
                    printButton:
                        enabled: false

        yextremes = @chart.yAxis[0].getExtremes()
        @chart.yAxis[0].setExtremes(0, yextremes.dataMax*(($("#chart").height()-70)/($("#chart").height()-90-$("#meta").height())), true, false)

    update: (data) =>
        # TODO: only add/remove modified series
        @chart.series[0].remove() while @chart.series.length != 0

        if @bookworm.state.xAxis.unit == "int"
            @chart.xAxis[0].setCategories((x for x in [0..data[0].data.length])) 
        else
            @chart.xAxis[0].setCategories(null)

        for series in data
            @chart.addSeries series, false

        @chart.redraw()
        yextremes = @chart.yAxis[0].getExtremes()
        @chart.yAxis[0].setExtremes(0, yextremes.dataMax*(($("#chart").height()-70)/($("#chart").height()-90-$("#meta").height())), true)

    resetZoom: () =>
        @chart.xAxis[0].setExtremes null, null


class Bookworm

    constructor: () ->
        @colorManager = new ColorManager()
        @apiManager = new APIManager()

        $.when(@apiManager.getOptions()).done (options) =>

            options = @apiManager.processOptions options, @colorManager

            console.log options

            @metadata = options.metadata

            @state = new State options.settings.dbname, options.xOptions[0]

            # Add initial queries
            for query in options["queries"]
                @state.addQuery query

            @uiManager = new UIManager @, @state, options.xOptions

            @uiManager.setName options.settings.sourceName

            $.when(@apiManager.getCounts @state).done (counts) =>
                $("#header, #meta, #chart").fadeIn 600
                @chart = new Chart (@apiManager.processCounts @state, counts), @
                $("#reset-zoom").click () =>
                    @chart.resetZoom()
                    @uiManager.toggleResetZoom false

            # Render x-axis options and give them click events
            for xOption in options.xOptions
                optionUI = @uiManager.addXOption xOption
                ((state, uiManager) ->
                    x = xOption
                    optionUI.click () =>
                        state.xAxis = x
                        state.xRange = x.range
                        uiManager.selectXOption x
                        $("#chart .cover").click()
                )(@state, @uiManager)

            $("#meta .settings .case").click @toggleCase

            $("#meta").click () =>
                @state.state = "changing"
                @uiManager.coverChart()

            $("#chart .x-axis .selector").click () =>
                @uiManager.showXOptions()
                # @state.state = "changing"
                # @uiManager.coverChart()

            $(document).keypress (e) =>
                if e.which == 13 and @state.state == "changing"
                    $("#chart .cover").click()

            $("#chart .cover").click () =>
                @state.state = "loading"
                @uiManager.hideChart()
                $.when(@apiManager.getCounts @state).done (counts) =>
                    if @state.state != "changing"
                        @uiManager.showChart()
                        @chart.update(@apiManager.processCounts @state, counts)
                        @state.state = "loaded"

    toggleCase: () =>
        @state.caseSensitive = !@state.caseSensitive
        @uiManager.toggleCase()



$.when(windowLoaded.promise()).done ->


bookworm = null

$(window).load () ->
    bookworm = new Bookworm()
    windowLoaded.resolve("done")


$ ->




