require File.dirname(__FILE__) + '/spec_helper'


#
#  Resque-loner specific specs. I'm shooting right through the stack here and just
#  test the outcomes, because the implementation will change soon and the tests run
#  quite quickly.
#

class SomeJob
  @queue = :some_queue
end

class SomeUniqueJob < Resque::Plugins::Loner::UniqueJob
  @queue = :other_queue
  def self.perform
  end
end

describe "Resque" do

  before(:each) do
    Resque.redis.flushall
    Resque.size(:other_queue).should == 0
    Resque.size(:some_queue).should == 0
  end
  
  describe "Jobs" do
    it "can put multiple normal jobs on a queue" do
      Resque.enqueue SomeJob, "foo"
      Resque.enqueue SomeJob, "foo"
      Resque.size(:some_queue).should == 2
    end
  
    it "only one of the same job sits in a queue" do
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.size(:other_queue).should == 1
    end
  
    it "should allow the same jobs to be executed one after the other" do
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.size(:other_queue).should == 1

      Resque.reserve(:other_queue)
      Resque.size(:other_queue).should == 0

      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.size(:other_queue).should == 1
    end
  
    it "should be robust regarding hash attributes" do
      Resque.enqueue SomeUniqueJob, :bar => 1, :foo => 2
      Resque.enqueue SomeUniqueJob, :foo => 2, :bar => 1
      Resque.size(:other_queue).should == 1
    end
  
    it "should be robust regarding hash attributes (JSON does not distinguish between string and symbol)" do
      Resque.enqueue SomeUniqueJob, :bar => 1, :foo  => 1
      Resque.enqueue SomeUniqueJob, :bar => 1, "foo" => 1
      Resque.size(:other_queue).should == 1
    end
  
    it "should mark jobs as unqueued, when Job.destroy is killing them" do
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.size(:other_queue).should == 1

      Resque::Job.destroy(:other_queue, SomeUniqueJob)
      Resque.size(:other_queue).should == 0

      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.size(:other_queue).should == 1
    end
    
    it "should mark jobs as unqueued, when they raise an exception" do
      worker = Resque::Worker.new(:other_queue)
      Resque.enqueue( SomeUniqueJob, "foo" ).should == "OK"
      Resque.enqueue( SomeUniqueJob, "foo" ).should == "EXISTED"
      Resque.size(:other_queue).should == 1

      SomeUniqueJob.should_receive(:perform).with("foo").and_raise "I beg to differ"
      worker.process
      Resque.size(:other_queue).should == 0

      Resque.enqueue( SomeUniqueJob, "foo" ).should == "OK"
      Resque.enqueue( SomeUniqueJob, "foo" ).should == "EXISTED"
      Resque.size(:other_queue).should == 1
    end
    
    it "should report if a job is queued or not" do
      Resque.enqueue SomeUniqueJob, "foo"
      Resque.enqueued?(SomeUniqueJob, "foo").should be_true
      Resque.enqueued?(SomeUniqueJob, "bar").should be_false
    end

    it "should report if a job is in a special queue or not" do
      Resque.enqueue_to :special_queue, SomeUniqueJob, "foo"
      Resque.enqueued_in?( :special_queue, SomeUniqueJob, "foo").should be_true
      Resque.enqueued?( SomeUniqueJob, "foo").should be_false
    end

    it "should not be able to report if a non-unique job was enqueued" do
      Resque.enqueued?(SomeJob).should be_nil
    end
    
  end
  
  describe "Queues" do
    
    it "should allow for jobs to be queued in other queues than their default" do
      Resque.enqueue_to :yet_another_queue, SomeJob, 22
      
      Resque.size(:some_queue).should == 0
      Resque.size(:yet_another_queue).should ==1
    end
    
    it "should allow for jobs to be dequeued from other queues than their default" do
      Resque.enqueue_to :yet_another_queue, SomeJob, 22
      Resque.enqueue SomeJob, 22
      
      Resque.size(:yet_another_queue).should == 1
      Resque.size(:some_queue).should == 1
      
      Resque.dequeue_from :yet_another_queue, SomeJob, 22
      
      Resque.size(:yet_another_queue).should == 0
      Resque.size(:some_queue).should == 1
    end

  end
end
