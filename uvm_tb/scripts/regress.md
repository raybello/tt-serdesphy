regress.py is a regression script that runs a given config file by passing -f <file>
After adding uvm_tb/scripts/ to $PATH

For example,
    regress.py -f uvm_tb/regression/config/nightly.csv


Step 1. Parse config
Get a build name <BUILD_NAME>, this will be the build name that all the test will be simulated against.
for lists look in uvm_tb/regression/lists for items under <TEST_LIST>
the test_lists are grouped based on <GROUP_NAME>
<BUILD_OPTIONS> defines extra arguments that can be supplied to <BUILD_SCRIPT>
<RUN_OPTIONS> define extra arguments for <RUN_SCRIPT>

Step 2. Parsing rules
If a csv field is empty but has been defined in earlier lines use the same value in that line. 
For example, <BUILD_NAME>, <BUILD_SCRIPT>,<RUN_SCRIPT>

Per line Required Fields (can be empty values)
<TEST_LIST>, <GROUP_NAME>, <RUN_OPTIONS>, <BUILD_SCRIPT>

Step 3. Prepare Build and Run commands
based on the parsed CSV files the result should be a list for run,build commands to be run.
All build commands should happen first before simulation files.

For example, (based on nightly.csv)
build.py -b tt_serdesphy
(parsed init_list.csv)
run.py -t init_sequence_test -s 1 -b tt_serdesphy
run.py -t init_sequence_test -s 1 -b tt_serdesphy
run.py -t reset_test -s 1 -b tt_serdesphy
run.py -t reset_test -s 1 -b tt_serdesphy
run.py -t clk_test -s 1 -b tt_serdesphy
run.py -t clk_test -s 1 -b tt_serdesphy
run.py -t basic_test -s 1 -b tt_serdesphy
run.py -t basic_test -s 1 -b tt_serdesphy
run.py -t pll_lock_test -s 1 -b tt_serdesphy
run.py -t pll_lock_test -s 1 -b tt_serdesphy
run.py -t tx_fifo_test -s 1 -b tt_serdesphy
run.py -t tx_fifo_test -s 1 -b tt_serdesphy
run.py -t test_mode_test -s 1 -b tt_serdesphy
run.py -t test_mode_test -s 1 -b tt_serdesphy
(parsed csr_list.csv)
...
(parsed prbs_list.csv)
...
(parsed loopback_list.csv)
...


4. Prepare a html page with navigation
report.html should be created. 

On the main page it should show all the builds in the config. for nightly.csv there is only one. 

So main page will have table with a build 'tt_serdesphy',
table headers are <build_name>,<log>, <status>, <build_time>,<build_command>
- when the name of the build is clicked it goes into the build view. this shows all the group names and the test count for each
- when the log is clicked a modal should popup to show the build log
- status should have a green 'build passed' or red 'build_failed' if it failed to build.

In the build view,
It shows the number of simulation in the group. as well as total/pass/fail counts
table header is as follows:
<group_name>, <total>, <pass>, <fail>

- If the name of the group is select the html navigates to the group view where all the individual tests under a group can be viewed
- If pass count is clicked it navigates to the group view but only shows passing tests, failed tests are filtered out
- if pass count is clicked it navigates to the group view but only shows failing tests, passing tests are filtered out

In the group view,
It shows all the testcases for that group in table form
table header is as follows:
<test_name>,<log>, <status>, <run_time>, <run_command>

- The test_name column shows the name of the test
the status column shows either 'test passed' or 'first UVM_ERROR in log'
- If log is clicked a modal should pop up with the log displayed

There are also some modifications required to the build scripts and run script to support this. 
namely
- ability to specify a build name in run.py -b <build_name> that way an executable is stored at build/<build_name>/<build_name> where build_name is also the name of the executable
- ability to specify addition options that can be passed to executable using -o <flag> or --option=<flag>
flag can be -o +DEFINE+, --option=Wno-context, -o +XPROP=1 etc
- the same ability should be present for run.py command options that can be passed to executable when simulating
- ability for run.py to specify a build to run against using -b <build_name>, the build exe will be located under uvm_tb/build/<build_name>/<build_name>



# Add to github actions for deployment on commit
This HTML should be hostable on github pages via an action under .github/workflows/test.yaml a new job called regression. 

The generated HTML page should get uploaded to GITHUB pages but should not coincide with existing viewer under .github/workflows/gds.yaml

The result page should be stored at url: raybello.github.io/tt-serdesphy/regression
Viewer stores its html under url: raybello.github.io/tt-serdesphy