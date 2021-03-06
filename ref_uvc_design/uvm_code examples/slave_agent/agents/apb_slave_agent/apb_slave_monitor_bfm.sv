//------------------------------------------------------------
//   Copyright 2010-2018 Mentor Graphics Corporation
//   All Rights Reserved Worldwide
//
//   Licensed under the Apache License, Version 2.0 (the
//   "License"); you may not use this file except in
//   compliance with the License.  You may obtain a copy of
//   the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in
//   writing, software distributed under the License is
//   distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
//   CONDITIONS OF ANY KIND, either express or implied.  See
//   the License for the specific language governing
//   permissions and limitations under the License.
//------------------------------------------------------------

//
// Interface Description:
//
//
interface apb_slave_monitor_bfm (input PCLK,
                                 input PRESETn,
                                 input[31:0] PADDR,
                                 input[31:0] PRDATA,
                                 input[31:0] PWDATA,
                                 input[31:0] PSEL,
                                 input PENABLE,
                                 input PWRITE,
                                 input PREADY,
                                 input PSLVERR);

  import apb_slave_agent_pkg::*;

//------------------------------------------
// Data Members
//------------------------------------------
  int apb_index = 0;
  apb_slave_monitor proxy;

//------------------------------------------
// Methods
//------------------------------------------
  function void set_apb_index(int index);
    apb_index = index;
  endfunction : set_apb_index

  task run();
    apb_slave_seq_item item;
    apb_slave_seq_item cloned_item;

    item = apb_slave_seq_item::type_id::create("item");

    forever begin
      // Detect the protocol event on the TBAI virtual interface
      @(posedge PCLK);
      if(PREADY && PSEL[apb_index])
        // Assign the relevant values to the analysis item fields
        begin
          item.addr = PADDR;
          item.rw = PWRITE;
          if(PWRITE)
            begin
              item.wdata = PWDATA;
            end
          else
            begin
              item.rdata = PRDATA;
            end
          // Clone and publish the cloned item to the subscribers
          $cast(cloned_item, item.clone());
          proxy.notify_transaction(cloned_item);
        end
    end
  endtask: run

  task wait_for_reset();
    wait (PRESETn);
  endtask : wait_for_reset
  
endinterface: apb_slave_monitor_bfm
