package ghcvm.runtime.stg;

import ghcvm.runtime.stg.StgClosure;
import ghcvm.runtime.stg.StgContext;

public class StgEnter extends StackFrame {
    public final StgClosure closure;

    public StgEnter(final StgClosure closure) {
        this.closure = closure;
    }

    @Override
    public void stackEnter(StgContext context) {
        StgClosure result = closure.evaluate(context);
        context.R(1, result);
    }

    @Override
    public StgClosure getClosure() {
        return closure;
    }
}
