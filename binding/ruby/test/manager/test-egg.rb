class TestEgg < Test::Unit::TestCase
  def setup
    @name = "child-milter"
    @egg = Milter::Manager::Egg.new(@name)
  end

  def test_new
    name = "child-milter"
    egg = Milter::Manager::Egg.new(name)
    assert_equal(name, egg.name)
  end

  def test_name
    new_name = "#{@name}-new"
    assert_not_equal(new_name, @egg.name)
    @egg.name = new_name
    assert_equal(new_name, @egg.name)
  end

  def test_connection_timeout
    connection_timeout = 29
    assert_equal(300, @egg.connection_timeout)
    @egg.connection_timeout = connection_timeout
    assert_equal(connection_timeout, @egg.connection_timeout)
  end

  def test_writing_timeout
    writing_timeout = 29
    assert_equal(10, @egg.writing_timeout)
    @egg.writing_timeout = writing_timeout
    assert_equal(writing_timeout, @egg.writing_timeout)
  end

  def test_reading_timeout
    reading_timeout = 29
    assert_equal(10, @egg.reading_timeout)
    @egg.reading_timeout = reading_timeout
    assert_equal(reading_timeout, @egg.reading_timeout)
  end

  def test_end_of_message_timeout
    end_of_message_timeout = 29
    assert_equal(200, @egg.end_of_message_timeout)
    @egg.end_of_message_timeout = end_of_message_timeout
    assert_equal(end_of_message_timeout, @egg.end_of_message_timeout)
  end

  def test_user_name
    user_name = "milter-user"
    assert_nil(@egg.user_name)
    @egg.user_name = user_name
    assert_equal(user_name, @egg.user_name)
  end

  def test_command
    command = "/usr/bin/milter-test-client"
    assert_nil(@egg.command)
    @egg.command = command
    assert_equal(command, @egg.command)
  end

  def test_applicable_condition
    assert_equal([], @egg.applicable_conditions)

    name = "S25R"
    condition = Milter::Manager::ApplicableCondition.new(name)
    @egg.add_applicable_condition(condition)
    assert_equal([name], @egg.applicable_conditions.collect {|cond| cond.name})

    @egg.clear_applicable_conditions
    assert_equal([], @egg.applicable_conditions)
  end

  def test_merge
    @egg.connection_timeout = 292.9
    @egg.writing_timeout = 2.9
    @egg.reading_timeout = 2.929
    @egg.end_of_message_timeout = 29.29
    @egg.user_name = "milter-user"
    @egg.command = "/usr/bin/milter-test-client"
    @egg.command_options = "-s inet:2929@localhost"
    @egg.connection_spec = "inet:2929@localhost"
    s25r = Milter::Manager::ApplicableCondition.new("S25R")
    disable = Milter::Manager::ApplicableCondition.new("Disable")
    @egg.add_applicable_condition(s25r)
    @egg.add_applicable_condition(disable)

    merged_egg = Milter::Manager::Egg.new("merged")
    merged_egg.merge(@egg)
    assert_in_delta(292.9, merged_egg.connection_timeout, 0.01)
    assert_in_delta(2.9, merged_egg.writing_timeout, 0.01)
    assert_in_delta(2.929, merged_egg.reading_timeout, 0.0001)
    assert_in_delta(29.29, merged_egg.end_of_message_timeout, 0.001)
    assert_equal("milter-user", merged_egg.user_name)
    assert_equal("/usr/bin/milter-test-client", merged_egg.command)
    assert_equal("-s inet:2929@localhost", merged_egg.command_options)
    assert_equal("inet:2929@localhost", merged_egg.connection_spec)
    assert_equal([s25r, disable], merged_egg.applicable_conditions)
  end

  def test_to_xml
    assert_equal(["<milter>",
                  "  <name>#{@name}</name>",
                  "</milter>"].join("\n") + "\n",
                 @egg.to_xml)

    @egg.signal_connect("to-xml") do |_, xml, indent|
      xml << " " * indent
      xml << "<additional-info>INFO</additional-info>\n"
    end
    assert_equal(["<milter>",
                  "  <name>#{@name}</name>",
                  "  <additional-info>INFO</additional-info>",
                  "</milter>"].join("\n") + "\n",
                 @egg.to_xml)
  end
end
