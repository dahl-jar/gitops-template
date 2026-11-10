final String KEPT_BUILDS = '50'

appJobs.each { appJob ->
  pipelineJob(appJob.name) {
    parameters {
      appJob.parameters.each { stringParam(it, '', '') }
      appJob.flags.each { booleanParam(it, false, '') }
    }
    properties {
      buildDiscarder {
        strategy {
          logRotator {
            daysToKeepStr('')
            numToKeepStr(KEPT_BUILDS)
            artifactDaysToKeepStr('')
            artifactNumToKeepStr('')
          }
        }
      }
      disableConcurrentBuilds()
    }
    definition {
      cps {
        script("@Library('ci') _\n" + appJob.call)
        sandbox(true)
      }
    }
  }
}
