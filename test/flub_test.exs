defmodule FlubTest do
  use ExUnit.Case
  require Flub

  setup do
    on_exit fn ->
      Flub.unsub
      :timer.sleep(10)
    end
  end

  test "multi subscribe gets one message for dual-match" do
    Flub.sub(%{}, :test)
    Flub.sub(%{a: _b}, :test)
    Flub.pub(%{a: 1}, :test)
    assert_receive(%Flub.Message{channel: :test, data: %{a: 1}, node: node})
    refute_receive(%Flub.Message{channel: :test, data: %{a: 1}})
  end


  test "unsub shuts down the dispatcher" do
    Flub.sub(:test)
    Flub.unsub(:test)
    :timer.sleep(10)
    assert Flub.open_channels == []
  end

  test "crashed dispatcher keeps subscribers" do
    Flub.sub(:test)
    Flub.EtsHelper.Dispatchers.find(:test)
    |> Process.exit(:kill)
    :timer.sleep(10)
    Flub.pub(:msg, :test)
    assert_receive(%Flub.Message{channel: :test, data: :msg})
  end

  test "subscribe and unsub" do
    msg = {:hello, "this is", %{a: 'test'}}

    # make sure we get the message
    Flub.sub(:test_chan)
    Flub.pub(msg, :test_chan)
    assert_receive %Flub.Message{data: ^msg, channel: :test_chan}

    # make sure we _don't_ get the message
    Flub.unsub(:test_chan)
    Flub.pub(msg, :test_chan)
    refute_receive ^msg
  end

  test "subscribe / unsub all" do
    msg = {:blah, [5, :a]}
    Flub.sub

    Flub.pub(msg)
    assert_receive(%Flub.Message{data: ^msg})

    Flub.unsub

    Flub.pub(msg)
    refute_receive(%Flub.Message{data: ^msg})
  end

  test "unsub on process termination" do
    parent = self

    # spawn a blocking subscriber process
    pid = spawn fn ->
      Flub.sub(:test)
      send parent, :subscribed
      receive do
        :block -> :block
      end
    end

    # wait for subscription
    receive do
      :subscribed -> Process.monitor pid
    after 100 ->
      raise "subscribed msg not received"
    end

    # verify pid is in subscriber list
    assert pid in Flub.subscribers(:test)

    # kill process and wait for :DOWN
    Process.exit pid, :kill
    receive do
      {:DOWN, _ref, :process, ^pid, :killed} -> :ok
    after 100 ->
      raise("monitor msg not received")
    end

    # verify pid is _not_ in subscriber list
    assert not pid in Flub.subscribers(:test)
  end

  defmodule TestStruct do
    defstruct value: 0, other: :default
  end
  test "pub filter" do
    myvar = 10
    msg = %TestStruct{value: 15}
    msg2 = %TestStruct{value: 10}
    Flub.sub(%TestStruct{value: ^myvar}, :test_chan)
    Flub.pub(msg, :test_chan)
    Flub.pub(msg2, :test_chan)


    refute_receive %Flub.Message{data: %TestStruct{value: 15}, channel: :test_chan}
    assert_receive %Flub.Message{data: %TestStruct{value: 10}, channel: :test_chan}
  end
  test "harmless other defaults" do
    myvar = 15
    msg = %TestStruct{value: myvar, other: :custom}
    Flub.sub(%TestStruct{value: ^myvar}, :test_chan)
    Flub.pub(msg, :test_chan)
    assert_receive %Flub.Message{data: %TestStruct{value: ^myvar, other: :custom}, channel: :test_chan}
  end

  test "node syntax" do
    Flub.sub(true, :test_channel, node)
    Flub.pub(:ok, :test_channel)
    assert_receive %Flub.Message{data: :ok, channel: :test_channel}
  end
  test "node syntax with pattern" do
    Flub.sub(%{a: _b}, MyChan, node)
    Flub.pub(%{a: 1}, MyChan)
    assert_receive %Flub.Message{data: %{a: 1}, channel: MyChan}
    Flub.pub(%{b: 1}, MyChan)
    refute_receive %Flub.Message{data: %{b: 1}, channel: MyChan}
  end
end
