ENV['RACK_ENV'] = 'test'

require 'rubygems'
require 'test/unit'
require 'rack/test'
require 'sinatra/base'
require_relative '../app'
require 'json'
