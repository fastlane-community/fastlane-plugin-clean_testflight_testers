module Fastlane
  module Actions
    class CleanTestflightTestersAction < Action
      def self.run(params)
        require 'spaceship'

        UI.message("Login to iTunes Connect (#{params[:username]})")
        Spaceship::Tunes.login(params[:username])
        Spaceship::Tunes.select_team
        UI.message("Login successful")

        UI.message("Fetching all TestFlight testers, this might take a few minutes, depending on the number of testers")

        # Convert from bundle identifier to app ID
        spaceship_app ||= Spaceship::Application.find(params[:app_identifier])
        UI.user_error!("Couldn't find app '#{params[:app_identifier]}' on the account of '#{params[:username]}' on iTunes Connect") unless spaceship_app
        app_id = spaceship_app.apple_id

        all_testers = Spaceship::TestFlight::Tester.all(app_id: app_id)
        counter = 0

        all_testers.each do |current_tester|
          days_since_status_change = (Time.now - current_tester.status_mod_time) / 60.0 / 60.0 / 24.0

          if current_tester.status == "invited"
            if days_since_status_change > params[:days_of_inactivity]
              remove_tester(current_tester, app_id, params[:dry_run]) # user got invited, but never installed a build... why would you do that?
              counter += 1
            end
          else
            # We don't really have a good way to detect whether the user is active unfortunately
            # So we can just delete users that had no sessions
            if days_since_status_change > params[:days_of_inactivity] && current_tester.session_count == 0
              # User had no sessions in the last e.g. 30 days, let's get rid of them
              remove_tester(current_tester, app_id, params[:dry_run])
              counter += 1
            end
          end
        end

        if params[:dry_run]
          UI.success("Didn't delete any testers, but instead only printed them out (#{counter}), disable `dry_run` to actually delete them 🦋")
        else
          UI.success("Successfully removed #{counter} testers 🦋")
        end
      end

      def self.remove_tester(tester, app_id, dry_run)
        if dry_run
          UI.message("TestFlight tester #{tester.email} seems to be inactive for app ID #{app_id}")
        else
          UI.message("Removing tester #{tester.email} due to inactivity from app ID #{app_id}...")
          tester.remove_from_app!(app_id: app_id)
          raise 'yolo'
        end
      end

      def self.description
        "Automatically remove TestFlight testers that are not actually testing your app"
      end

      def self.authors
        ["KrauseFx"]
      end

      def self.details
        "Automatically remove TestFlight testers that are not actually testing your app"
      end

      def self.available_options
        user = CredentialsManager::AppfileConfig.try_fetch_value(:itunes_connect_id)
        user ||= CredentialsManager::AppfileConfig.try_fetch_value(:apple_id)

        [
          FastlaneCore::ConfigItem.new(key: :username,
                                     short_option: "-u",
                                     env_name: "CLEAN_TESTFLIGHT_TESTERS_USERNAME",
                                     description: "Your Apple ID Username",
                                     default_value: user),
          FastlaneCore::ConfigItem.new(key: :app_identifier,
                                       short_option: "-a",
                                       env_name: "CLEAN_TESTFLIGHT_TESTERS_APP_IDENTIFIER",
                                       description: "The bundle identifier of the app to upload or manage testers (optional)",
                                       optional: true,
                                       default_value: ENV["TESTFLIGHT_APP_IDENTITIFER"] || CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier)),
          FastlaneCore::ConfigItem.new(key: :team_id,
                                       short_option: "-q",
                                       env_name: "CLEAN_TESTFLIGHT_TESTERS_TEAM_ID",
                                       description: "The ID of your iTunes Connect team if you're in multiple teams",
                                       optional: true,
                                       is_string: false, # as we also allow integers, which we convert to strings anyway
                                       default_value: CredentialsManager::AppfileConfig.try_fetch_value(:itc_team_id),
                                       verify_block: proc do |value|
                                         ENV["FASTLANE_ITC_TEAM_ID"] = value.to_s
                                       end),
          FastlaneCore::ConfigItem.new(key: :team_name,
                                       short_option: "-r",
                                       env_name: "CLEAN_TESTFLIGHT_TESTERS_TEAM_NAME",
                                       description: "The name of your iTunes Connect team if you're in multiple teams",
                                       optional: true,
                                       default_value: CredentialsManager::AppfileConfig.try_fetch_value(:itc_team_name),
                                       verify_block: proc do |value|
                                         ENV["FASTLANE_ITC_TEAM_NAME"] = value.to_s
                                       end),
          FastlaneCore::ConfigItem.new(key: :days_of_inactivity,
                                     short_option: "-k",
                                     env_name: "CLEAN_TESTFLIGHT_TESTERS_WAIT_PROCESSING_INTERVAL",
                                     description: "Numbers of days a tester has to be inactive for (no build uses) for them to be removed",
                                     default_value: 30,
                                     type: Integer,
                                     verify_block: proc do |value|
                                       UI.user_error!("Please enter a valid positive number of days") unless value.to_i > 0
                                     end),
          FastlaneCore::ConfigItem.new(key: :dry_run,
                                     short_option: "-d",
                                     env_name: "CLEAN_TESTFLIGHT_TESTERS_DRY_RUN",
                                     description: "Only print inactive users, don't delete them",
                                     default_value: false,
                                     is_string: false)
        ]
      end

      def self.is_supported?(platform)
        platform == :ios
      end
    end
  end
end
