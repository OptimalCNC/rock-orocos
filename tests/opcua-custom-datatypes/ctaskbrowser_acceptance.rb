#!/usr/bin/env ruby

require "optparse"
require "pty"
require "timeout"

options = {}
OptionParser.new do |parser|
  parser.on("--client PATH") { |value| options[:client] = value }
  parser.on("--endpoint URL") { |value| options[:endpoint] = value }
  parser.on("--component NAME") { |value| options[:component] = value }
end.parse!

%i[client endpoint component].each do |key|
  abort("missing --#{key.to_s.tr('_', '-')}") unless options[key]
end

ANSI_ESCAPE = /\e\[[0-?]*[ -\/]*[@-~]/
SESSION_TIMEOUT = 30
TERMINATION_TIMEOUT = 2

def normalize_transcript(transcript)
  transcript.gsub(ANSI_ESCAPE, "").delete("\r")
end

def terminate_child(pid)
  return unless pid

  begin
    Process.kill("TERM", pid)
  rescue Errno::ESRCH
  end

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
             TERMINATION_TIMEOUT
  loop do
    begin
      waited_pid, = Process.waitpid2(pid, Process::WNOHANG)
      return if waited_pid
    rescue Errno::ECHILD
      return
    end
    break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep 0.05
  end

  begin
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
  end
  begin
    Process.wait(pid)
  rescue Errno::ECHILD
  end
end

def run_session(options, commands)
  transcript = +""
  child_pid = nil
  status = nil

  begin
    Timeout.timeout(SESSION_TIMEOUT) do
      PTY.spawn(
        { "TERM" => "dumb" },
        options.fetch(:client),
        "--import", "orocos_opcua_fixture",
        options.fetch(:endpoint), options.fetch(:component)
      ) do |reader, writer, pid|
        child_pid = pid
        writer.write(commands.join("\n") + "\n")
        writer.flush
        begin
          loop { transcript << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
        end
        _, status = Process.wait2(pid)
        child_pid = nil
      end
    end
  rescue Timeout::Error
    terminate_child(child_pid)
    child_pid = nil
    abort(
      "ctaskbrowser-opcua timed out after #{SESSION_TIMEOUT}s:\n" \
      "#{normalize_transcript(transcript)}"
    )
  rescue StandardError => error
    terminate_child(child_pid)
    child_pid = nil
    abort(
      "ctaskbrowser-opcua failed with #{error.class}: #{error.message}\n" \
      "#{normalize_transcript(transcript)}"
    )
  ensure
    terminate_child(child_pid)
  end

  transcript = normalize_transcript(transcript)
  abort("ctaskbrowser-opcua failed:\n#{transcript}") unless status&.success?
  transcript
end

def command_segments(transcript, component, commands)
  starts = []
  commands.each do |command|
    prompt = /^#{Regexp.escape(component)} \[[^\]\n]+\]> #{Regexp.escape(command)}$/
    match = transcript.match(prompt, starts.last&.fetch(1) || 0)
    abort("command not echoed as a prompt line: #{command}\n#{transcript}") unless match

    starts << [match.begin(0), match.end(0)]
  end

  commands.each_index.to_h do |index|
    finish = starts[index + 1]&.fetch(0) || transcript.length
    [commands[index], transcript[starts[index].fetch(1)...finish]]
  end
end

def expect_segment(segments, command, pattern, transcript)
  return if segments.fetch(command).match?(pattern)

  abort(
    "unexpected result for #{command}: expected #{pattern.inspect}\n" \
    "#{transcript}"
  )
end

first_commands = [
  "PointAttribute",
  "EnvelopeAttribute",
  "EnvelopeConstant",
  "PointArrayAttribute",
  "PointAttribute.x",
  "EnvelopeAttribute.point.x",
  "EnvelopeAttribute.quality",
  "EnvelopeProperty.point.y",
  "PointArrayAttribute[0].x",
  "EnvelopeEcho(EnvelopeAttribute)",
  "EnvelopeAttribute.point.x = 101",
  "EnvelopeAttribute.quality = 102",
  "EnvelopeProperty.point.y = 103",
  "PointArrayAttribute[0].x = 201",
  "EnvelopeConstant.point.x = 999",
  "EnvelopeConstant.point.x",
  "quit"
]

first_transcript = run_session(options, first_commands)
first = command_segments(
  first_transcript, options.fetch(:component), first_commands
)
expect_segment(first, "PointAttribute",
               /=\s*Point\{\s*10(?:\.0+)?,\s*20(?:\.0+)?\}/,
               first_transcript)
expect_segment(
  first, "EnvelopeAttribute",
  /=\s*Envelope\{\s*Point\{\s*10(?:\.0+)?,\s*20(?:\.0+)?\},\s*30\}/,
  first_transcript
)
expect_segment(
  first, "EnvelopeConstant",
  /=\s*Envelope\{\s*Point\{\s*3(?:\.0+)?,\s*4(?:\.0+)?\},\s*5\}/,
  first_transcript
)
expect_segment(
  first, "PointArrayAttribute",
  /Point\{\s*10(?:\.0+)?,\s*11(?:\.0+)?\}.*Point\{\s*12(?:\.0+)?,\s*13(?:\.0+)?\}/m,
  first_transcript
)
expect_segment(first, "PointAttribute.x", /=\s*10(?:\.0+)?\b/,
               first_transcript)
expect_segment(first, "EnvelopeAttribute.point.x", /=\s*10(?:\.0+)?\b/,
               first_transcript)
expect_segment(first, "EnvelopeAttribute.quality", /=\s*30\b/,
               first_transcript)
expect_segment(first, "EnvelopeProperty.point.y", /=\s*20(?:\.0+)?\b/,
               first_transcript)
expect_segment(first, "PointArrayAttribute[0].x", /=\s*10(?:\.0+)?\b/,
               first_transcript)
expect_segment(
  first, "EnvelopeEcho(EnvelopeAttribute)",
  /=\s*Envelope\{\s*Point\{\s*10(?:\.0+)?,\s*20(?:\.0+)?\},\s*30\}/,
  first_transcript
)
expect_segment(
  first, "EnvelopeConstant.point.x = 999",
  /Fatal Semantic error:.*Cannot assign constant/m, first_transcript
)
expect_segment(first, "EnvelopeConstant.point.x", /=\s*3(?:\.0+)?\b/,
               first_transcript)

second_commands = [
  "EnvelopeAttribute.point.x",
  "EnvelopeAttribute.quality",
  "EnvelopeProperty.point.y",
  "PointArrayAttribute[0].x",
  "EnvelopeConstant.point.x",
  "quit"
]

second_transcript = run_session(options, second_commands)
second = command_segments(
  second_transcript, options.fetch(:component), second_commands
)
expect_segment(second, "EnvelopeAttribute.point.x", /=\s*101(?:\.0+)?\b/,
               second_transcript)
expect_segment(second, "EnvelopeAttribute.quality", /=\s*102\b/,
               second_transcript)
expect_segment(second, "EnvelopeProperty.point.y", /=\s*103(?:\.0+)?\b/,
               second_transcript)
expect_segment(second, "PointArrayAttribute[0].x", /=\s*201(?:\.0+)?\b/,
               second_transcript)
expect_segment(second, "EnvelopeConstant.point.x", /=\s*3(?:\.0+)?\b/,
               second_transcript)

puts "ctaskbrowser-opcua custom datatype acceptance passed"
