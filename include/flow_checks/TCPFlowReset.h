/*
 *
 * (C) 2013-24 - ntop.org
 *
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 */

#ifndef _FLOW_RESET_H
#define _FLOW_RESET_H

#include "ntop_includes.h"

class TCPFlowReset : public FlowCheck {
 private:
  void checkFlowReset(Flow *f);
 public:
  TCPFlowReset() : FlowCheck(ntopng_edition_community, true /* Packet Interfaces only */,
                true /* Exclude for nEdge */, false /* NOT only for nEdge */,
                false /* has_protocol_detected */,
                false /* has_periodic_update */, true /* has_flow_end */){};  
  ~TCPFlowReset(){};

  void flowEnd(Flow *f);
  FlowAlert *buildAlert(Flow *f);

  std::string getName() const {
    return (std::string("tcp_flow_reset"));
  }
};

#endif /* _FLOW_RESET_H */
