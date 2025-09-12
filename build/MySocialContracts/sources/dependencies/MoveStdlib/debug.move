// Copyright (c) Mysten Labs, Inc.
// Copyright (c) The Social Proof Foundation, LLC.
// SPDX-License-Identifier: Apache-2.0

/// Module providing debug functionality.
module std::debug;

public native fun print<T>(x: &T);

public native fun print_stack_trace();
