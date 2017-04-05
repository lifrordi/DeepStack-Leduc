project = 'DeepStack Leduc'
title = 'DeepStack for Leduc Hold\'em'
description = 'DeepStack for Leduc Hold\'em and variants'
format = 'markdown'
backtick_references=false
kind_names={topic='Manual'}
file = { '../Source/',
		 exclude = { '../Source/Tree/Tests', 
					 '../Source/Lookahead/Tests',
					 '../Source/Nn/next_round_value_test.lua',
					 '../Source/ACPC/Tests'}
		}
readme = { 'manual/tutorial.md',
		   'manual/internals.md' }
dir = '.'