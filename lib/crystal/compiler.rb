require 'llvm/transforms/ipo'
require 'llvm/transforms/scalar'

module Crystal
  class Compiler
    include Crystal

    attr_reader :command

    def initialize
      require 'optparse'

      @options = {}
      OptionParser.new do |opts|
        opts.on('-o ', 'Output filename') do |output|
          @options[:output_filename] = output
        end
        opts.on('-run ', 'Execute filename') do |run|
          @run = true
        end
        opts.on('-graph ', 'Render type graph') do |graph|
          @graph = true
        end
      end.parse!

      if !@options[:output_filename] && ARGV.length > 0
        @options[:output_filename] = File.basename(ARGV[0], File.extname(ARGV[0]))
      end

      o_flag = @options[:output_filename] ? "-o #{@options[:output_filename]} " : ''
      @command = "llc | clang -x assembler #{o_flag}-"
    end

    def compile
      begin
        node = parse ARGF.read
        mod = infer_type node
        graph node, mod, @options[:output_filename] if @graph

        llvm_mod = build node, mod
        engine = LLVM::JITCompiler.new llvm_mod
        optimize llvm_mod, engine
      rescue Crystal::Exception => ex
        puts ex.message
        exit 1
      rescue Exception => ex
        puts ex
        puts ex.backtrace
        exit 1
      end

      if @run
        engine.run_function llvm_mod.functions["main"]
      else
        reader, writer = IO.pipe
        Thread.new do
          llvm_mod.write_bitcode(writer)
          writer.close
        end

        pid = spawn command, in: reader
        Process.waitpid pid
      end
    end

    def optimize(mod, engine)
      pm = LLVM::PassManager.new engine
      pm.inline!
      pm.gdce!
      pm.instcombine!
      pm.reassociate!
      pm.gvn!
      pm.mem2reg!
      pm.simplifycfg!
      pm.tailcallelim!
      pm.loop_unroll!
      pm.loop_deletion!
      pm.loop_rotate!

      5.times { pm.run mod }
    end
  end
end