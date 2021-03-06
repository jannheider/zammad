class App.TicketZoomArticleView extends App.Controller
  constructor: ->
    super
    @articleController = {}
    @run()

  execute: (params) =>
    @ticket_article_ids = params.ticket_article_ids
    @run()

  run: =>
    all = []
    for ticket_article_id in @ticket_article_ids
      controllerKey = ticket_article_id.toString()
      if !@articleController[controllerKey]
        el = $('<div></div>')
        @articleController[controllerKey] = new ArticleViewItem(
          ticket:     @ticket
          object_id:  ticket_article_id
          el:         el
          ui:         @ui
          highligher: @highligher
        )
        all.push el
    @el.append(all)

    # check elements to remove
    for article_id, controller of @articleController
      exists = false
      for localArticleId in @ticket_article_ids
        if localArticleId.toString() is article_id.toString()
          exists = true
      if !exists
        controller.remove()
        delete @articleController[article_id.toString()]

class ArticleViewItem extends App.ObserverController
  model: 'TicketArticle'
  observe:
    from: true
    to: true
    cc: true
    subject: true
    body: true
    internal: true
    preferences: true

  elements:
    '.textBubble-content':           'textBubbleContent'
    '.textBubble-overflowContainer': 'textBubbleOverflowContainer'

  events:
    'click .textBubble':   'toggleMetaWithDelay'
    'click .textBubble a': 'stopPropagation'
    'click .js-unfold':    'unfold'

  constructor: ->
    super
    @seeMore = false

    # set expand of text area only once
    @bind('ui::ticket::shown', (data) =>
      return if data.ticket_id.toString() isnt @ticket.id.toString()

      # set highlighter
      @setHighlighter()

      # set see more
      @setSeeMore()
    )

  setHighlighter: =>
    return if @el.is(':hidden')
    # use delay do no ui blocking
    #@highligher.loadHighlights(@object_id)
    d = =>
      @highligher.loadHighlights(@object_id)
    @delay(d, 200)

  render: (article) =>

    # set @el attributes
    @el.addClass("ticket-article-item #{article.sender.name.toLowerCase()}")
    @el.attr('data-id', article.id)
    @el.attr('id', "article-#{article.id}")
    if article.internal
      @el.addClass('is-internal')
    else
      @el.removeClass('is-internal')

    # prepare html body
    if article.content_type is 'text/html'
      body = article.body
      if article.preferences && article.preferences.signature_detection
        signatureDetected = '<span class="js-signatureMarker"></span>'
        body = body.replace(signatureDetected, '')
        body = body.split('<br>')
        body.splice(article.preferences.signature_detection, 0, signatureDetected)
        body = body.join('<br>')
      else
        body = App.Utils.signatureIdentify(body)
      article['html'] = body
    else

      # client signature detection
      bodyHtml = App.Utils.text2html(article.body)
      article['html'] = App.Utils.signatureIdentify(bodyHtml)

      # if no signature detected or within frist 25 lines, check if signature got detected in backend
      if article['html'] is bodyHtml || (article.preferences && article.preferences.signature_detection < 25)
        signatureDetected = false
        body = article.body
        if article.preferences && article.preferences.signature_detection
          signatureDetected = '########SIGNATURE########'
          # coffeelint: disable=no_unnecessary_double_quotes
          body = body.split("\n")
          body.splice(article.preferences.signature_detection, 0, signatureDetected)
          body = body.join("\n")
          # coffeelint: enable=no_unnecessary_double_quotes
        if signatureDetected
          body = App.Utils.textCleanup(body)
          article['html'] = App.Utils.text2html(body)
          article['html'] = article['html'].replace(signatureDetected, '<span class="js-signatureMarker"></span>')

    # check if email link need to be updated
    if article.type.name is 'email'
      if !article.preferences.links
        article.preferences.links = [
          {
            name: 'Raw'
            url: "#{@Config.get('api_path')}/ticket_article_plain/#{article.id}"
            target: '_blank'
          }
        ]

    if article.preferences.delivery_message
      @html App.view('ticket_zoom/article_view_delivery_failed')(
        ticket:     @ticket
        article:    article
        isCustomer: @permissionCheck('ticket.customer')
      )
      return
    if article.sender.name is 'System'
    #if article.sender.name is 'System' && article.preferences.perform_origin is 'trigger'
      @html App.view('ticket_zoom/article_view_system')(
        ticket:     @ticket
        article:    article
        isCustomer: @permissionCheck('ticket.customer')
      )
      return
    @html App.view('ticket_zoom/article_view')(
      ticket:     @ticket
      article:    article
      isCustomer: @permissionCheck('ticket.customer')
    )

    new App.WidgetAvatar(
      el:        @$('.js-avatar')
      object_id: article.created_by_id
      size:      40
    )

    new App.TicketZoomArticleActions(
      el:              @$('.js-article-actions')
      ticket:          @ticket
      article:         article
      lastAttributres: @lastAttributres
    )

    # set see more
    @shown = false
    a = =>
      @setSeeMore()
    @delay(a, 50)

    # set highlighter
    @setHighlighter()

  # set see more options
  setSeeMore: =>
    return if @el.is(':hidden')
    return if @shown
    @shown = true

    maxHeight               = 560
    minHeight               = 90
    bubbleContent           = @textBubbleContent
    bubbleOvervlowContainer = @textBubbleOverflowContainer

    # expand if see more is already clicked
    if @seeMore
      bubbleContent.css('height', 'auto')
      bubbleOvervlowContainer.addClass('hide')
      return

    # reset bubble heigth and "see more" opacity
    bubbleContent.css('height', '')
    bubbleOvervlowContainer.css('opacity', '')

    # remember offset of "see more"
    signatureMarker = bubbleContent.find('.js-signatureMarker')
    if !signatureMarker.get(0)
      signatureMarker = bubbleContent.find('div [data-signature=true]')
    offsetTop = signatureMarker.position()

    # safari - workaround
    # in safari somethimes the marker is directly on top via .top and inspector but it isn't
    # in this case use the next element
    if offsetTop && offsetTop.top is 0
      offsetTop = signatureMarker.next('div, p, br').position()

    # remember bubble heigth
    heigth = bubbleContent.height()

    # get marker heigth
    if offsetTop
      markerHeight = offsetTop.top

    # if signature marker exists and heigth is within maxHeight
    if markerHeight && markerHeight < maxHeight
      newHeigth = offsetTop.top + 30
      if newHeigth < minHeight
        newHeigth = minHeight
      bubbleContent.attr('data-height', heigth)
      bubbleContent.css('height', "#{newHeigth}px")
      bubbleOvervlowContainer.removeClass('hide')

    # if heigth is higher then maxHeight
    else if heigth > maxHeight
      bubbleContent.attr('data-height', heigth)
      bubbleContent.css('height', "#{maxHeight}px")
      bubbleOvervlowContainer.removeClass('hide')
    else
      bubbleOvervlowContainer.addClass('hide')

  stopPropagation: (e) ->
    e.stopPropagation()

  toggleMetaWithDelay: (e) =>
    # allow double click select
    # by adding a delay to the toggle

    if @lastClick and +new Date - @lastClick < 80
      clearTimeout(@toggleMetaTimeout)
    else
      @toggleMetaTimeout = setTimeout(@toggleMeta, 80, e)
      @lastClick = +new Date

  toggleMeta: (e) =>
    e.preventDefault()

    animSpeed      = 300
    article        = $(e.target).closest('.ticket-article-item')
    metaTopClip    = article.find('.article-meta-clip.top')
    metaBottomClip = article.find('.article-meta-clip.bottom')
    metaTop        = article.find('.article-content-meta.top')
    metaBottom     = article.find('.article-content-meta.bottom')

    if @elementContainsSelection(article.get(0))
      @stopPropagation(e)
      return false

    if !metaTop.hasClass('hide')
      article.removeClass('state--folde-out')

      # scroll back up
      article.velocity 'scroll',
        container: article.scrollParent()
        offset: -article.offset().top - metaTop.outerHeight()
        duration: animSpeed
        easing: 'easeOutQuad'

      metaTop.velocity
        properties:
          translateY: 0
          opacity: [ 0, 1 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'
          complete: -> metaTop.addClass('hide')

      metaBottom.velocity
        properties:
          translateY: [ -metaBottom.outerHeight(), 0 ]
          opacity: [ 0, 1 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'
          complete: -> metaBottom.addClass('hide')

      metaTopClip.velocity({ height: 0 }, animSpeed, 'easeOutQuad')
      metaBottomClip.velocity({ height: 0 }, animSpeed, 'easeOutQuad')
    else
      article.addClass('state--folde-out')
      metaBottom.removeClass('hide')
      metaTop.removeClass('hide')

      # balance out the top meta height by scrolling down
      article.velocity('scroll',
        container: article.scrollParent()
        offset: -article.offset().top + metaTop.outerHeight()
        duration: animSpeed
        easing: 'easeOutQuad'
      )

      metaTop.velocity
        properties:
          translateY: [ 0, metaTop.outerHeight() ]
          opacity: [ 1, 0 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'

      metaBottom.velocity
        properties:
          translateY: [ 0, -metaBottom.outerHeight() ]
          opacity: [ 1, 0 ]
        options:
          speed: animSpeed
          easing: 'easeOutQuad'

      metaTopClip.velocity({ height: metaTop.outerHeight() }, animSpeed, 'easeOutQuad')
      metaBottomClip.velocity({ height: metaBottom.outerHeight() }, animSpeed, 'easeOutQuad')

  unfold: (e) ->
    e.preventDefault()
    e.stopPropagation()

    @seeMore = true

    bubbleContent           = @textBubbleContent
    bubbleOvervlowContainer = @textBubbleOverflowContainer

    bubbleOvervlowContainer.velocity
      properties:
        opacity: 0
      options:
        duration: 300

    bubbleContent.velocity
      properties:
        height: bubbleContent.attr('data-height')
      options:
        duration: 300
        complete: -> bubbleOvervlowContainer.addClass('hide')

  isOrContains: (node, container) ->
    while node
      if node is container
        return true
      node = node.parentNode
    false

  elementContainsSelection: (el) ->
    sel = window.getSelection()
    if sel.rangeCount > 0 && sel.toString()
      for i in [0..sel.rangeCount-1]
        if !@isOrContains(sel.getRangeAt(i).commonAncestorContainer, el)
          return false
      return true
    false

  remove: =>
    @el.remove()
