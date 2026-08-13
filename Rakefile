# frozen_string_literal: true

require "rake/testtask"
require "standard/rake"

Rake::TestTask.new { |t| t.test_files = FileList["test/**/*_test.rb"] }

task default: %i[test standard]
