module OnTeardown
  def on_teardown
    define_singleton_method(:teardown) do
      yield
      super()
    end
  end
end
