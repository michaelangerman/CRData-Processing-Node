#!/usr/bin/env ruby
#
################################################################################
# File:         processing_node.rb
# Description:  This is the main loop processing requests on worker machine.
#               It continuously polls the server for jobs to run. Once a job
#               is available to run, it calls the relevant R script through
#               RSRuby interface. It will block on the job is complete before
#               accepting a new job. This cycle is repeated forever until the
#               worker machine is shut down.
# License:      Creative Common License, CRdata.org project
################################################################################

require 'rubygems'
require 'rest_client'
require 'logger'

require 'job'
require 'global'

class ProcessingNode
  attr_reader :server_node, :site

  def initialize(server)
    @server_node = server
    @site = RestClient::Resource.new(@server_node)
  end

  def run
    while true
      begin
        # main processing loop that accepts new job from server, server address
        # is passed as argument to the program.

        # STEP 1: Fetch new job from server
        # STEP 2: If there are no jobs, sleep and try again
        # STEP 3: If there is a job found in STEP 1, then parse the payload
        # STEP 4: Assuming new job, create tempdir()
        # STEP 5: Save the r-script that was fetched as part of new job payload
        # STEP 5: Fetch Datasets, if any from S3 if indicated in job payload.
        #         Currently the datasets is not yet supported in Phase 1 so not
        #         implemented yet.
        # STEP 6: Call RSRuby wrapper code to execute the R script, this is a
        #         currently blocking call, not multithreaded etc.
        # STEP 7: Next step is calling storage wrapper code to store results
        #         and logs in S3.
        # STEP 8: Mark status of the job on server as 'done' or 'cancelled'
        # STEP 9: Repeat STEP 1.
        job = nil
        begin
          # STEP 1
          job = fetch_next_job()

          # STEP 3-5
          job.fetch_source_code if !job.nil?
          job.fetch_params if !job.nil?

          # STEP 6
          job.run if !job.nil?

          # STEP 7
          job.store_results_and_logs if !job.nil?

          # STEP 7
          job.store_data if !job.nil?

          # STEP 8
          job_completed(job) if !job.nil?
        rescue => err
          Global.logger.fatal(err)

          # STEP 8
          job_completed(job) if !job.nil?

          # STEP 7
          job.store_results_and_logs if !job.nil?

          job = nil
        end
      rescue => err2
        Global.logger.fatal(err2)
      end
      # STEP 2 & STEP 9
      sleep(10)
    end
  end

  def fetch_next_job
    # issue command to fetch next job
    begin
      xml_response = @site['jobs_queues/run_next_job'].put '', {:content_length => '0', :content_type => 'text/xml'}
      begin
        job = Job.new(xml_response, @server_node)
      rescue Exception => alt_xml_body
        # for some reason we have to try both methods...
        job = Job.new(xml_response.body, @server_node)
      end
      return job
    rescue Exception => exception_not_found
      return_status = exception_not_found.to_s
      # don't report too much stuff to log, unnecessary logging
      # ResourceNotFound is reported when there are no new jobs
      Global.logger.fatal(return_status) if !/ResourceNotFound/.match(return_status)
      return nil
    end
  end

  def job_completed(job)
    # mark status of the job on server
    if job.job_status == Global::SUCCESSFUL_JOB
      #success_length = "success=true".length
      #@site["jobs/#{job.get_id}/done.xml?success=true"].put '', {:content_length => '0', :content_type => 'text/plain'}
      Global.logger.info('COMPLETED JOB, MARKING JOB SUCCESSFUL')

      system("curl -X PUT -H 'Content-length: 0' http://#{@server_node}/jobs/#{job.get_id}/done.xml?success=true")
    else
      #success_length = "success=false".length
      #@site["jobs/#{job.get_id}/done.xml?success=false"].put '', {:content_length => '0', :content_type => 'text/plain'}
      system("curl -X PUT -H 'Content-length: 0' http://#{@server_node}/jobs/#{job.get_id}/done.xml?success=false")
      Global.logger.info('FAILED JOB, MARKING JOB FAILURE')
    end
  end
end

#################################################################
# MAIN PROGRAM CALL (this is the START)
# initialize and launch, ensure command line has server address
Global.set_logger Logger.new(Global::LOG_FILE)
Global.set_root_dir
Global.set_results_dir

server = ARGV[0]

processing_node = ProcessingNode.new(server)
processing_node.run
