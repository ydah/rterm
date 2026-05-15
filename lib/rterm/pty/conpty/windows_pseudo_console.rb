# frozen_string_literal: true

require "fiddle"
require "fiddle/import"

module RTerm
  class ConPTY
    class ProcessBackend
      class WindowsPseudoConsole
        class Error < StandardError; end

        ExitStatus = Struct.new(:exitstatus, :termsig)

        CREATE_UNICODE_ENVIRONMENT = 0x00000400
        EXTENDED_STARTUPINFO_PRESENT = 0x00080000
        INFINITE = 0xffff_ffff
        PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016
        WAIT_OBJECT_0 = 0
        ERROR_BROKEN_PIPE = 109

        if Gem.win_platform?
          module Kernel32
            extend Fiddle::Importer
            dlload "kernel32"

            extern "int CloseHandle(void*)"
            extern "void ClosePseudoConsole(void*)"
            extern "int CreatePipe(void*, void*, void*, unsigned long)"
            extern "int CreateProcessW(void*, void*, void*, void*, int, unsigned long, void*, void*, void*, void*)"
            extern "int CreatePseudoConsole(int, void*, void*, unsigned long, void*)"
            extern "void DeleteProcThreadAttributeList(void*)"
            extern "unsigned long GetLastError()"
            extern "int GetExitCodeProcess(void*, void*)"
            extern "int InitializeProcThreadAttributeList(void*, unsigned long, unsigned long, void*)"
            extern "int PeekNamedPipe(void*, void*, unsigned long, void*, void*, void*)"
            extern "int ReadFile(void*, void*, unsigned long, void*, void*)"
            extern "int ResizePseudoConsole(void*, int)"
            extern "int TerminateProcess(void*, unsigned int)"
            extern "int UpdateProcThreadAttribute(void*, unsigned long, size_t, void*, size_t, void*, void*)"
            extern "unsigned long WaitForSingleObject(void*, unsigned long)"
            extern "int WriteFile(void*, void*, unsigned long, void*, void*)"
          end
        end

        class PipeReader
          def initialize(handle)
            @handle = handle
            @closed = false
          end

          def read_nonblock(length)
            raise IOError, "closed stream" if closed?

            available = bytes_available
            raise IO::EAGAINWaitReadable if available.zero?

            read_bytes([length.to_i, available].min)
          end

          def close
            return if closed?

            Kernel32.CloseHandle(@handle)
            @closed = true
          end

          def closed?
            @closed
          end

          private

          def bytes_available
            available_pointer = "\0".b * 4
            result = Kernel32.PeekNamedPipe(@handle, nil, 0, nil, available_pointer, nil)
            handle_pipe_error("PeekNamedPipe") if result.zero?

            available_pointer.unpack1("L<")
          end

          def read_bytes(length)
            buffer = "\0".b * length
            read_pointer = "\0".b * 4
            result = Kernel32.ReadFile(@handle, buffer, length, read_pointer, nil)
            handle_pipe_error("ReadFile") if result.zero?

            buffer.byteslice(0, read_pointer.unpack1("L<")).to_s
          end

          def handle_pipe_error(function)
            error = Kernel32.GetLastError()
            raise EOFError if error == ERROR_BROKEN_PIPE

            raise IOError, "#{function} failed with Windows error #{error}"
          end
        end

        class PipeWriter
          def initialize(handle)
            @handle = handle
            @closed = false
          end

          def write(data)
            raise IOError, "closed stream" if closed?

            bytes = data.to_s.b
            offset = 0
            while offset < bytes.bytesize
              written_pointer = "\0".b * 4
              chunk = bytes.byteslice(offset, bytes.bytesize - offset)
              result = Kernel32.WriteFile(@handle, chunk, chunk.bytesize, written_pointer, nil)
              handle_pipe_error("WriteFile") if result.zero?

              written = written_pointer.unpack1("L<")
              raise IOError, "WriteFile wrote no bytes" if written.zero?

              offset += written
            end
            bytes.bytesize
          end

          def flush
            self
          end

          def close
            return if closed?

            Kernel32.CloseHandle(@handle)
            @closed = true
          end

          def closed?
            @closed
          end

          private

          def handle_pipe_error(function)
            error = Kernel32.GetLastError()
            raise Errno::EPIPE if error == ERROR_BROKEN_PIPE

            raise IOError, "#{function} failed with Windows error #{error}"
          end
        end

        attr_reader :stdin, :stdout, :pid

        def self.supported?
          Gem.win_platform?
        end

        def initialize(command:, args:, env:, cwd:, cols:, rows:)
          raise Error, "native Windows process backend is only available on Windows" unless self.class.supported?

          @command = command
          @args = args
          @env = env
          @cwd = cwd
          @cols = cols
          @rows = rows
          @hpc = nil
          @process_handle = nil
          @closed = false
          spawn
        end

        def resize(cols, rows)
          return false if @hpc.nil?

          Kernel32.ResizePseudoConsole(@hpc, coord(cols, rows)).zero?
        end

        def terminate(exit_code = 1)
          return false if @process_handle.nil?

          Kernel32.TerminateProcess(@process_handle, exit_code).zero? == false
        end

        def wait
          return ExitStatus.new(nil, nil) if @process_handle.nil?

          result = Kernel32.WaitForSingleObject(@process_handle, INFINITE)
          raise last_error("WaitForSingleObject") unless result == WAIT_OBJECT_0

          code_pointer = "\0".b * 4
          raise last_error("GetExitCodeProcess") if Kernel32.GetExitCodeProcess(@process_handle, code_pointer).zero?

          ExitStatus.new(code_pointer.unpack1("L<"), nil)
        ensure
          close_process_handle
        end

        def close
          return false if @closed

          @closed = true
          @stdin&.close unless @stdin&.closed?
          @stdout&.close unless @stdout&.closed?
          close_pseudo_console
          true
        rescue IOError
          false
        end

        private

        def spawn
          input_read, input_write = create_pipe
          output_read, output_write = create_pipe
          create_pseudo_console(input_read, output_write)
          create_child_process
          close_handle(input_read)
          close_handle(output_write)
          input_read = nil
          output_write = nil
          @stdin = PipeWriter.new(input_write)
          @stdout = PipeReader.new(output_read)
          input_write = nil
          output_read = nil
        rescue StandardError
          @stdin&.close
          @stdout&.close
          close_handle(input_read)
          close_handle(input_write)
          close_handle(output_read)
          close_handle(output_write)
          close_pseudo_console
          close_process_handle
          raise
        end

        def create_pipe
          read_pointer = empty_pointer
          write_pointer = empty_pointer
          raise last_error("CreatePipe") if Kernel32.CreatePipe(read_pointer, write_pointer, nil, 0).zero?

          [read_pointer.unpack1(pointer_pack), write_pointer.unpack1(pointer_pack)]
        end

        def create_pseudo_console(input_read, output_write)
          handle_pointer = empty_pointer
          result = Kernel32.CreatePseudoConsole(coord(@cols, @rows), input_read, output_write, 0, handle_pointer)
          raise hresult_error("CreatePseudoConsole", result) unless result.zero?

          @hpc = handle_pointer.unpack1(pointer_pack)
        end

        def create_child_process
          attribute_list = build_attribute_list
          startup_info = build_startup_info(attribute_list)
          process_information = "\0".b * process_information_size
          command_line = wide_string(command_line_string)
          cwd = @cwd ? wide_string(@cwd) : nil
          env_block = environment_block
          flags = EXTENDED_STARTUPINFO_PRESENT
          flags |= CREATE_UNICODE_ENVIRONMENT if env_block

          result = Kernel32.CreateProcessW(
            nil,
            command_line,
            nil,
            nil,
            0,
            flags,
            env_block,
            cwd,
            startup_info,
            process_information
          )
          raise last_error("CreateProcessW") if result.zero?

          parse_process_information(process_information)
        ensure
          Kernel32.DeleteProcThreadAttributeList(attribute_list) if attribute_list
        end

        def build_attribute_list
          size_pointer = "\0".b * size_t_size
          Kernel32.InitializeProcThreadAttributeList(nil, 1, 0, size_pointer)
          size = size_pointer.unpack1(size_t_pack)
          raise last_error("InitializeProcThreadAttributeList") if size.zero?

          attribute_list = "\0".b * size
          unless Kernel32.InitializeProcThreadAttributeList(attribute_list, 1, 0, size_pointer).nonzero?
            raise last_error("InitializeProcThreadAttributeList")
          end

          result = Kernel32.UpdateProcThreadAttribute(
            attribute_list,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            @hpc,
            pointer_size,
            nil,
            nil
          )
          raise last_error("UpdateProcThreadAttribute") if result.zero?

          attribute_list
        end

        def build_startup_info(attribute_list)
          startup_info = "\0".b * startup_info_ex_size
          startup_info[0, 4] = [startup_info_ex_size].pack("L<")
          startup_info[startup_info_attribute_offset, pointer_size] = [Fiddle::Pointer[attribute_list].to_i].pack(pointer_pack)
          startup_info
        end

        def parse_process_information(process_information)
          @process_handle = process_information.byteslice(0, pointer_size).unpack1(pointer_pack)
          thread_handle = process_information.byteslice(pointer_size, pointer_size).unpack1(pointer_pack)
          @pid = process_information.byteslice(pointer_size * 2, 4).unpack1("L<")
          close_handle(thread_handle)
        end

        def command_line_string
          ([quote_argument(@command)] + @args.map { |arg| quote_argument(arg.to_s) }).join(" ")
        end

        def quote_argument(argument)
          return '""' if argument.empty?
          return argument unless argument.match?(/[\s"]/)

          quoted = +"\""
          backslashes = 0
          argument.each_char do |char|
            case char
            when "\\"
              backslashes += 1
            when '"'
              quoted << ("\\" * ((backslashes * 2) + 1))
              quoted << char
              backslashes = 0
            else
              quoted << ("\\" * backslashes)
              quoted << char
              backslashes = 0
            end
          end
          quoted << ("\\" * (backslashes * 2))
          quoted << "\""
        end

        def environment_block
          return nil if @env.empty?

          ENV.to_h.merge(@env)
             .sort_by { |key, _value| key.upcase }
             .map { |key, value| "#{key}=#{value}" }
             .join("\0")
             .then { |block| wide_string("#{block}\0") }
        end

        def wide_string(value)
          "#{value}\0".encode("UTF-16LE").b
        end

        def coord(cols, rows)
          ((rows.to_i & 0xffff) << 16) | (cols.to_i & 0xffff)
        end

        def empty_pointer
          "\0".b * pointer_size
        end

        def pointer_size
          Fiddle::SIZEOF_VOIDP
        end

        def pointer_pack
          pointer_size == 8 ? "Q<" : "L<"
        end

        def size_t_size
          Fiddle::SIZEOF_SIZE_T
        end

        def size_t_pack
          size_t_size == 8 ? "Q<" : "L<"
        end

        def startup_info_ex_size
          pointer_size == 8 ? 112 : 72
        end

        def startup_info_attribute_offset
          pointer_size == 8 ? 104 : 68
        end

        def process_information_size
          (pointer_size * 2) + 8
        end

        def close_handle(handle)
          return if handle.nil? || handle.zero?

          Kernel32.CloseHandle(handle)
        end

        def close_pseudo_console
          return if @hpc.nil?

          Kernel32.ClosePseudoConsole(@hpc)
          @hpc = nil
        end

        def close_process_handle
          return if @process_handle.nil?

          close_handle(@process_handle)
          @process_handle = nil
        end

        def last_error(function)
          Error.new("#{function} failed with Windows error #{Kernel32.GetLastError()}")
        end

        def hresult_error(function, result)
          code = result & 0xffff_ffff
          Error.new("#{function} failed with HRESULT 0x#{code.to_s(16)}")
        end
      end
    end
  end
end
