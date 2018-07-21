-module(testable_vnode).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

-callback inject_failure(term(), reference(), binary(), binary()) -> ok.