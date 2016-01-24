require 'httpclient'

require_dependency 'mailer'

module TelegramMailerPatch
  def self.included(base) # :nodoc:
    
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    base.class_eval do
      alias_method_chain :issue_add, :telegram
      alias_method_chain :issue_edit, :telegram
    end
  end
  
  module ClassMethods
    
    def speak(msg, channel, attachment=nil, token=nil)
      Rails.logger.info("TELEGRAM SPEAK #{msg} => #{channel}")
      token = Setting.plugin_redmine_telegram[:telegram_bot_token] if not token
      username = Setting.plugin_redmine_telegram[:username]
      icon = Setting.plugin_redmine_telegram[:icon]
      Rails.logger.info("Token #{token}")
      Rails.logger.info("username #{username}")
      Rails.logger.info("icon #{icon}")
      telegram_url = "https://api.telegram.org/bot#{token}/sendMessage"
      Rails.logger.info("telegram_url #{telegram_url}")
      params = {}
      

      params[:chat_id] = channel if channel
      params[:parse_mode] = "Markdown"
      
      # if icon and not icon.empty?
      #   if icon.start_with? ':'
      #     params[:icon_emoji] = icon
      #   else
      #     params[:icon_url] = icon
      #   end
      # end
      
      if attachment
        msg = msg +"\r\n"+attachment[:text]
        for field_item in attachment[:fields] do
          msg = msg +"\r\n"+"> *"+field_item[:title]+":* "+field_item[:value]
        end
      end

      params[:text] = msg
      
      begin
        client = HTTPClient.new
        # client.ssl_config.cert_store.set_default_paths
        # client.ssl_config.ssl_version = "SSLv23"
        # client.post_async url, {:payload => params.to_json}
        client.post_async(telegram_url, params)
      rescue
        # Bury exception if connection error
      end
    end

  end
  
  module InstanceMethods
    # Adds a rates tab to the user administration page
    def issue_add_with_telegram(issue, to_users, cc_users)
      msg = "*[#{escape issue.project}]* _#{escape issue.author}_ created [#{escape issue}](#{object_url issue})#{mentions issue.description}"
      Rails.logger.info("TELEGRAM Add Issue [#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] (#{issue.status.name}) #{issue.subject}")
      issue_add_without_telegram(issue, to_users, cc_users)
    end

    def issue_edit_with_telegram(journal, to_users, cc_users)
      
      issue = journal.journalized
      issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue, :anchor => "change-#{journal.id}")
      users = to_users + cc_users
      journal_details = journal.visible_details(users.first)
      
      Rails.logger.info("Ready for MSG")
      
      msg = "*[#{issue.project.name}]* _#{journal.user.to_s}_ updated [#{issue.subject}](#{issue_url}) #{mentions journal.notes}"
      
      channel = channel_for_project issue.project
      url = url_for_project issue.project

      attachment = {}
      attachment[:text] = escape journal.notes if journal.notes
      attachment[:fields] = journal.details.map { |d| detail_to_field d }
      
      Rails.logger.info("TELEGRAM Edit Issue [#{issue.project.name} - #{issue.tracker.name} #{issue.id}] (#{issue.status.name}) #{issue.subject}")
      
      Mailer.speak(msg, channel, attachment, url)
      
      issue_edit_without_telegram(journal, to_users, cc_users)
    end

    def escape(msg)
      msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("[", "\[").gsub("]", "\]")
    end

    def object_url(obj)
      Rails.application.routes.url_for(obj.event_url({:host => Setting.host_name, :protocol => Setting.protocol}))
    end

    def url_for_project(proj)
      return nil if proj.blank?

      cf = ProjectCustomField.find_by_name("Telegram BOT Token")

      return [
        (proj.custom_value_for(cf).value rescue nil),
        (url_for_project proj.parent),
        Setting.plugin_redmine_telegram[:telegram_bot_token],
      ].find{|v| v.present?}
    end

    def channel_for_project(proj)
      return nil if proj.blank?

      cf = ProjectCustomField.find_by_name("Telegram Channel")

      val = [
        (proj.custom_value_for(cf).value rescue nil),
        (channel_for_project proj.parent),
        Setting.plugin_redmine_telegram[:channel],
      ].find{|v| v.present?}

      # Channel name '-' is reserved for NOT notifying
      return nil if val.to_s == '-'
      val
    end

    def detail_to_field(detail)
      if detail.property == "cf"
        key = CustomField.find(detail.prop_key).name rescue nil
        title = key
      elsif detail.property == "attachment"
        key = "attachment"
        title = I18n.t :label_attachment
      else
        key = detail.prop_key.to_s.sub("_id", "")
        title = I18n.t "field_#{key}"
      end

      short = true
      value = escape detail.value.to_s

      case key
      when "title", "subject", "description"
        short = false
      when "tracker"
        tracker = Tracker.find(detail.value) rescue nil
        value = escape tracker.to_s
      when "project"
        project = Project.find(detail.value) rescue nil
        value = escape project.to_s
      when "status"
        status = IssueStatus.find(detail.value) rescue nil
        value = escape status.to_s
      when "priority"
        priority = IssuePriority.find(detail.value) rescue nil
        value = escape priority.to_s
      when "category"
        category = IssueCategory.find(detail.value) rescue nil
        value = escape category.to_s
      when "assigned_to"
        user = User.find(detail.value) rescue nil
        value = escape user.to_s
      when "fixed_version"
        version = Version.find(detail.value) rescue nil
        value = escape version.to_s
      when "attachment"
        attachment = Attachment.find(detail.prop_key) rescue nil
        value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
      when "parent"
        issue = Issue.find(detail.value) rescue nil
        value = "<#{object_url issue}|#{escape issue}>" if issue
      end

      value = "-" if value.empty?

      result = { :title => title, :value => value }
      result[:short] = true if short
      result
    end

    def mentions text
      names = extract_usernames text
      names.present? ? "\nTo: " + names.join(', ') : nil
    end

    def extract_usernames text = ''
      # slack usernames may only contain lowercase letters, numbers,
      # dashes and underscores and must start with a letter or number.
      text.scan(/@[a-z0-9][a-z0-9_\-]*/).uniq
    end

  end
end

Mailer.send(:include, TelegramMailerPatch)