# NOTE: only doing this in development as some production environments (Heroku)
# NOTE: are sensitive to local FS writes, and besides -- it's just not proper
# NOTE: to have a dev-mode tool do its thing in production.
db_tasks = %w[
  db:migrate
  db:seed
  db:prepare
  db:setup
  db:reset
  db:schema:load
  db:test:prepare
  db:create
  db:drop
].freeze
task_args = ARGV.dup
task_args.concat(Rake.application.top_level_tasks) if defined?(Rake) && Rake.application
task_args = task_args.compact.uniq
skip_for_db = task_args.any? { |arg| arg.start_with?('db:') || db_tasks.include?(arg) }
skip_annotate = ENV['SKIP_ANNOTATE'] == '1' || skip_for_db

if Rails.env.development? && !skip_annotate
  begin
    require 'annotate_rb'

    runner_singleton = AnnotateRb::Runner.singleton_class
    unless runner_singleton.method_defined?(:run_without_rescue)
      runner_singleton.class_eval do
        alias_method :run_without_rescue, :run
        def run(args)
          run_without_rescue(args)
        rescue StandardError => e
          warn "[auto_annotate_models] skipped: #{e.class}: #{e.message}"
        end
      end
    end

    AnnotateRb::Core.load_rake_tasks

    task :set_annotation_options do
      # You can override any of these by setting an environment variable of the
      # same name.
      AnnotateRb::Options.set_defaults(
        'additional_file_patterns' => [],
        'routes' => 'false',
        'models' => 'true',
        'position_in_routes' => 'before',
        'position_in_class' => 'before',
        'position_in_test' => 'before',
        'position_in_fixture' => 'before',
        'position_in_factory' => 'before',
        'position_in_serializer' => 'before',
        'show_foreign_keys' => 'true',
        'show_complete_foreign_keys' => 'false',
        'show_indexes' => 'true',
        'simple_indexes' => 'false',
        'model_dir' => [
          'app/models',
          'enterprise/app/models',
        ],
        'root_dir' => '',
        'include_version' => 'false',
        'require' => '',
        'exclude_tests' => 'true',
        'exclude_fixtures' => 'true',
        'exclude_factories' => 'true',
        'exclude_serializers' => 'true',
        'exclude_scaffolds' => 'true',
        'exclude_controllers' => 'true',
        'exclude_helpers' => 'true',
        'exclude_sti_subclasses' => 'false',
        'ignore_model_sub_dir' => 'false',
        'ignore_columns' => nil,
        'ignore_routes' => nil,
        'ignore_unknown_models' => 'false',
        'hide_limit_column_types' => 'integer,bigint,boolean',
        'hide_default_column_types' => 'json,jsonb,hstore',
        'skip_on_db_migrate' => 'false',
        'format_bare' => 'true',
        'format_rdoc' => 'false',
        'format_markdown' => 'false',
        'sort' => 'false',
        'force' => 'false',
        'frozen' => 'false',
        'classified_sort' => 'true',
        'trace' => 'false',
        'wrapper_open' => nil,
        'wrapper_close' => nil,
        'with_comment' => 'true'
      )
    end
  rescue StandardError => e
    warn "[auto_annotate_models] skipped: #{e.class}: #{e.message}"
  end
end
