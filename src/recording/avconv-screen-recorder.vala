/*
Peek Copyright (c) 2015-2017 by Philipp Wolfer <ph.wolfer@gmail.com>

This file is part of Peek.

This software is licensed under the GNU General Public License
(version 3 or later). See the LICENSE file in this distribution.
*/

using Peek.PostProcessing;

namespace Peek.Recording {

  [Version (deprecated = true, replacement = "FfmpegScreenRecorder")]
  public class AvconvScreenRecorder : CommandLineScreenRecorder {
    ~AvconvScreenRecorder () {
      cancel ();
    }

    public override bool record (RecordingArea area) {
      try {
        // Cancel running recording
        cancel ();

        string display = Environment.get_variable ("DISPLAY");
        if (display == null) {
          display = ":0";
        }

        var args = new Array<string> ();
        args.append_val ("avconv");
        // args.append_val ("-loglevel");
        // args.append_val ("debug");
        args.append_val ("-f");
        args.append_val ("x11grab");
        args.append_val ("-show_region");
        args.append_val ("0");
        args.append_val ("-framerate");
        args.append_val (framerate.to_string ());
        args.append_val ("-video_size");
        args.append_val (area.width.to_string () + "x" + area.height.to_string ());

        if (!capture_mouse) {
          stderr.printf ("capture_mouse is set to false, but avconv does not support disabling the mouse cursor\n");
          // args.append_val ("-draw_mouse");
          // args.append_val ("0");
        }

        args.append_val ("-i");
        args.append_val (display + "+" + area.left.to_string () + "," + area.top.to_string ());

        string extension;

        if (output_format == OUTPUT_FORMAT_WEBM) {
          extension = Utils.get_file_extension_for_format (output_format);
          args.append_val ("-codec:v");
          // args.append_val ("libvpx-vp9");
          args.append_val ("libvpx");
          args.append_val ("-qmin");
          args.append_val ("10");
          args.append_val ("-qmax");
          args.append_val ("50");
          args.append_val ("-crf");
          args.append_val ("13");
          args.append_val ("-b:v");
          args.append_val ("1M");
        } else if (output_format == OUTPUT_FORMAT_MP4) {
          extension = Utils.get_file_extension_for_format (output_format);
          args.append_val ("-codec:v");
          args.append_val ("libx264");
          args.append_val ("-preset");
          args.append_val ("fast");
        } else if (output_format == OUTPUT_FORMAT_GIF) {
          extension = "pam";
          args.append_val ("-codec:v");
          args.append_val ("pam");
          args.append_val ("-f");
          args.append_val ("rawvideo");
        } else {
          stderr.printf (
            "Error: Output format %s no supported by avconv screen recorder.\n",
            output_format);
          return false;
        }

        args.append_val ("-filter:v");
        var filter = "scale=iw/" + downsample.to_string () + ":-1";
        if (output_format == OUTPUT_FORMAT_MP4) {
          filter += ", crop=iw-mod(iw\\,2):ih-mod(ih\\,2)";
        }

        args.append_val (filter);

        temp_file = Utils.create_temp_file (extension);
        args.append_val ("-y");
        args.append_val (temp_file);

        return spawn_record_command (args.data);
      } catch (FileError e) {
        stderr.printf ("Error: %s\n", e.message);
        return false;
      }
    }

    public static bool is_available () throws PeekError {
      return Utils.check_for_executable ("avconv");
    }

    protected override bool is_exit_status_success (int status) {
      return Process.term_sig (status) == ProcessSignal.INT ||
        Process.exit_status (status) == 0 ||
        Process.exit_status (status) == 255;
    }

    protected override void stop_recording () {
      Posix.kill (pid, Posix.SIGINT);
    }

    protected override async File? run_post_processors_async () {
      var file = File.new_for_path (temp_file);

      PostProcessor? post_processor = null;
      if (output_format == OUTPUT_FORMAT_GIF) {
        post_processor = new ImagemagickPostProcessor (framerate);
      }

      if (post_processor != null) {
        active_post_processor = post_processor;
        file = yield post_processor.process_async (file);
        active_post_processor = null;
        remove_temp_file ();
      }

      temp_file = null;

      return file;
    }
  }

}
