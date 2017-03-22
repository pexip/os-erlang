/* ``Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * 
 * The Initial Developer of the Original Code is Ericsson Utvecklings AB.
 * Portions created by Ericsson are Copyright 1999, Ericsson Utvecklings
 * AB. All Rights Reserved.''
 * 
 *     $Id$
 */

/*
 * Author: Rickard Green
 *
 * Description: Implementation of a driver with a smaller major
 *              driver version than allowed on load.
 */

#define VSN_MISMATCH_DRV_NAME_STR		"smaller_major_vsn_drv"
#define VSN_MISMATCH_DRV_NAME			smaller_major_vsn_drv
#define VSN_MISMATCH_DRV_MAJOR_VSN_DIFF		(ERL_DRV_MIN_REQUIRED_MAJOR_VERSION_ON_LOAD - ERL_DRV_EXTENDED_MAJOR_VERSION - 1)
#define VSN_MISMATCH_DRV_MINOR_VSN_DIFF		0
 
#include "vsn_mismatch_drv_impl.c"
