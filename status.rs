extern mod std;
extern mod extra;

use std::io;
use std::path;
use std::run::process_output;
use std::str;
use extra::time;
use std::rt::io::timer::sleep;

static GREEN: &'static str = "#00EE55";
static GREY:  &'static str = "#DDDDDD";

fn load(filename: ~str) -> ~str {
  let read_result: Result<@Reader, ~str>;
  read_result = io::file_reader(~path::Path(filename));

  match read_result {
    Ok(file) => {
      return file.read_c_str();
    },
    Err(e) => {
      println(fmt!("Error reading lines: %?", e));
      return ~"";
    }
  }
}

fn colour(s: ~str, c: &'static str) -> ~str {
  return "\\" + c + "\\" + s;
}

fn run(hostname: &~str) {


  let curTime = time::now();
  let sDate: ~str = colour(curTime.strftime("%a %Y-%m-%d"),GREY);
  let sTime: ~str = colour(curTime.strftime("%H:%M"),GREEN);
  let sTZ: ~str   = colour(curTime.strftime("%z"),GREY);


  let acpiOutput = process_output(&"/usr/bin/acpi",&[]);
  let acpiStatus = str::from_utf8(acpiOutput.output);

  let parts = acpiStatus.word_iter().to_owned_vec();

  let percentage = parts[3].trim_chars(&',');


  let acpiThermalOutput = process_output(&"/usr/bin/acpi",&[~"-t"]);
  let acpiThermalStatus = str::from_utf8(acpiThermalOutput.output);
  let thermalParts = acpiThermalStatus.word_iter().to_owned_vec();

  let temp = thermalParts[3].trim_chars(&',');


  let msg = fmt!("%s %s %s %s %s %s", percentage, temp, sDate, sTime, sTZ, *hostname);

  process_output(&"/usr/bin/wmfs",&[~"-s",~"0",msg]);
}

fn main() {
  let rawHostname = load(~"/etc/hostname");
  let hostname: ~str = rawHostname.trim().to_str();
  loop {
    run(&hostname);
    sleep(5000);
  }
}
