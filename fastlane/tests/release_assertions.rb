# Tiny dependency-free assertion runner, matching beta_safety_test.rb's
# offline approach. Bundler excludes undeclared test-framework gems.
class ReleaseAssertions
  def self.run!
    tests = public_instance_methods(false).grep(/^test_/).sort
    tests.each do |name|
      instance = new
      begin
        instance.setup if instance.respond_to?(:setup)
        instance.public_send(name)
        puts "PASS: #{name}"
      ensure
        instance.teardown if instance.respond_to?(:teardown)
      end
    end
    puts "#{tests.length} #{name} tests passed (no Apple access)."
  end

  def assert(value, message = "Assertion failed")
    raise message unless value
  end

  def refute(value) = assert(!value, "Expected false value")
  def assert_equal(expected, actual) = assert(expected == actual, "Expected #{expected.inspect}, got #{actual.inspect}")
  def assert_empty(value) = assert(value.empty?, "Expected empty collection")

  def assert_raises(type)
    begin
      yield
    rescue type
      return
    end
    raise "Expected #{type}"
  end
end
