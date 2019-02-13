require 'coolline'
require 'rouge'
require 'shrb/configuration'

module Shrb
  class Readline
    def self.factory
      coolline = Coolline.new do |c|
        c.transform_proc = Configuration.transformer.transform
        c.completion_proc = Configuration.completor.completion

        c.bind "\C-d" do |cool|
          exit
        end
      end

      coolline
    end
  end
end
