
require 'rest-graph'

module RestGraph::RailsUtil
  def self.included controller
    controller.rescue_from(::RestGraph::Error){ |exception|
      logger.debug("DEBUG: RestGraph: action halt")
    }
  end

  def rest_graph_options
    @rest_graph_options ||=
      {:auto_redirect => true, :iframe => false, :authorize_options => {},
       :scope => 'offline_access,publish_stream,read_friendlists'}
  end

  def rest_graph_setup options={}
    rest_graph_options.merge!(options)

    # exchange the code with access_token
    if params[:code]
      rest_graph.authorize!(:code => params[:code],
                            :redirect_uri => normalized_request_uri)
      logger.debug(
        "DEBUG: RestGraph: detected code with #{normalized_request_uri}, " \
        "parsed: #{rest_graph.data.inspect}")
    end

    # if the code is bad or not existed,
    # check if there's one in session,
    # meanwhile, there the sig and access_token is correct,
    # that means we're in the context of iframe
    if !rest_graph.authorized? && params[:session]
      rest_graph.parse_json!(params[:session])
      logger.debug("DEBUG: RestGraph: detected session, parsed:" \
                   " #{rest_graph.data.inspect}")

      if rest_graph.authorized?
        @fb_sig_in_iframe = true
      else
        logger.warn("WARN: RestGraph: bad session: #{params[:session]}")
      end
    end

    # if we're not in iframe nor code passed,
    # we could check out cookies as well.
    if !rest_graph.authorized?
      rest_graph.parse_cookies!(cookies)
      logger.debug("DEBUG: RestGraph: detected cookies, parsed:" \
                   " #{rest_graph.data.inspect}")
    end

    # there are above 3 ways to check the user identity!
    # if nor of them passed, then we can suppose the user
    # didn't authorize for us
  end

  # override this if you need different app_id and secret
  def rest_graph
    @rest_graph ||= RestGraph.new(
      :error_handler => method(:rest_graph_authorize),
        :log_handler => method(:rest_graph_log))
  end

  def rest_graph_authorize error=nil
    logger.warn("WARN: RestGraph: #{error.inspect}") if error

    @rest_graph_authorize_url = rest_graph.authorize_url(
      {:redirect_uri => normalized_request_uri,
       :scope        => rest_graph_options[:scope]}.
      merge(rest_graph_options[:authorize_options]))

    logger.debug("DEBUG: RestGraph: redirect to #{@authorize_url}")

    rest_graph_authorize_redirect if rest_graph_options[:auto_redirect]
    raise ::RestGraph::Error.new(error)
  end

  # override this if you want the simple redirect_to
  def rest_graph_authorize_redirect
    if !@fb_sig_in_iframe && !rest_graph_options[:iframe]
      redirect_to @rest_graph_authorize_url

    else
      render :inline => <<-HTML
      <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
      "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
      <html>
        <head>
        <script type="text/javascript">
          window.top.location.href = '<%= @authorize_url %>'
        </script>
        <noscript>
          <meta http-equiv="refresh" content="0;url=<%= h @rest_graph_authorize_url %>" />
          <meta http-equiv="window-target" content="_top" />
        </noscript>
        </head>
        <body>
          <div>Please <a href="<%= h @rest_graph_authorize_url %>" target="_top">authorize</a> if this page is not automatically redirected.</div>
        </body>
      </html>
      HTML
    end
  end

  def rest_graph_log duration, url
    logger.debug("DEBUG: RestGraph: spent #{duration} requesting #{url}")
  end

  def normalized_request_uri
    if @fb_sig_in_iframe
      "http://apps.facebook.com/" \
      "#{RestGraph.default_canvas}#{request.request_uri}"
    else
      request.url
    end.sub(/[\&\?]session=[^\&]+/, '').
        sub(/[\&\?]code=[^\&]+/, '')
  end
end

RestGraph::RailsController = RestGraph::RailsUtil
