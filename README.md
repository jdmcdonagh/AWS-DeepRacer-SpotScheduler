# AWS DeepRacer Spot Scheduler

This work builds upon [Esa Laine's DeepRacer templates](https://github.com/EsaLaine/deepracer-templates) repository to allow multiple runs to be scheduled with one line.

The following line:

    ./create-routine <base-stack-name> <track-config-name> 
can schedule a series of cloned runs. Each run can have a unique action space, reward function and hyperparameter definition.
## Benefits

 - Initiate multiple cloned runs using different settings with one line
 - Over 30x more cost-effective than training in the DeepRacer console.
 - Minimises interruptions by using a ‘capacity optimised’ allocation strategy
 - Safe termination and automatic reboots when an instance is interrupted
