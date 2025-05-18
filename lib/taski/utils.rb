require 'fileutils'
require 'tmpdir'

module Taski
  class Utils < FileUtils
    def rm

    end

    def rm_f
    end

    def rm_rf

    end

    def cp

    end

    def cp_r

    end

    def mkdir

    end

    def mkdir_p

    end

    def mktmpdir

    end

    def cmd(command, info = nil, ret = false)
      puts "exec: #{info}" if info
      puts command

      if ret
        ret = `#{command}`.chomp
        if $?.exited?
          ret
        else
          raise "Failed to execute command: #{command}"
        end
      else
        system command, exception: true
      end
    end
  end
end
